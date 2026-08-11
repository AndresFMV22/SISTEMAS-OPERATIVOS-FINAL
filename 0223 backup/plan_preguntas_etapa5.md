# Etapa 5 — Plan previo de exploración del dominio

**Examen No. 1 — Tópicos Avanzados de Bases de Datos — UPB 202620**
Andrés Felipe Martínez — ID SIGAA 000549446 — PostgreSQL 18
José Miguel Jaramillo — ID SIGAA 000210186 — MS SQL Server 2025

Proyecto: Cadena de frío de medicamentos — "Distri-Cold"

---

## Propósito de este documento

El enunciado pide construir la pregunta antes de responderla, y advierte sobre el problema
detectado en el simulacro: preguntas que admiten Window Functions por adorno pero que se
resuelven igual con un `group by` plano. Para evitarlo se levantó primero el inventario de
preguntas habituales del dominio, se ordenó por qué tan recurrentes son, y se trabajó sobre
las tres del fondo de la lista.

## Top 10 de preguntas recurrentes en una cadena de frío

Ordenadas de la más habitual a la menos explorada.

| # | Pregunta | Cómo se resuelve normalmente | ¿Necesita Window Functions? |
|---|---|---|---|
| 1 | ¿Cuántas unidades hay disponibles de cada lote y en qué almacén? | `join` + `group by` | No |
| 2 | ¿Qué lotes están próximos a vencer? | `where` sobre `fecha_vencimiento` | No |
| 3 | ¿En qué condiciones debe conservarse cada medicamento? | `join` directo | No |
| 4 | ¿Cuál es la temperatura promedio de cada almacén? | `avg` + `group by` | No |
| 5 | ¿Cuántas lecturas salieron del rango permitido? | `count` con `filter` | No |
| 6 | ¿Qué almacenes concentran más inventario? | `sum` + `order by` + `limit` | No |
| 7 | ¿Cómo se distribuye el inventario por ciudad y tipo de almacén? | `group by` de dos niveles | No |
| 8 | **¿Cuánto tiempo estuvo expuesto el inventario, no cuántas veces?** | — | **Sí** |
| 9 | **¿Las desviaciones son picos aislados o rachas sostenidas?** | — | **Sí** |
| 10 | **¿Qué inventario concreto estaba en riesgo durante cada desviación?** | — | **Sí** |

Las siete primeras se responden con agregación convencional. Tres de ellas son, de hecho,
las consultas de la Etapa 4 de este mismo examen.

## Las tres menos populares, que son las que interesan

### 8. La duración, no el conteo

La métrica que todo el mundo reporta es "693 de 1.000 lecturas fuera de rango". Es un número
grande y llamativo que no dice nada accionable, porque no distingue una desviación de veinte
minutos de una de tres semanas. Para el medicamento lo que importa es el tiempo acumulado de
exposición, no cuántas veces se registró.

Medir duración obliga a mirar la lectura vecina: una lectura aislada no tiene duración, la
adquiere solo al compararla con la siguiente en el tiempo.

### 9. Picos aislados contra rachas sostenidas

Veinte lecturas sueltas fuera de rango repartidas en seis meses y veinte lecturas
consecutivas fuera de rango son el mismo número y dos problemas completamente distintos: la
primera situación sugiere ruido del sensor o aperturas de puerta; la segunda, un equipo de
refrigeración averiado. El `count` plano las confunde porque agrupa por valor, y lo que
distingue una racha es la **posición** de las filas, no su contenido.

### 10. Qué inventario estaba realmente en riesgo

Este fue el hallazgo que reorientó la pregunta final. Al revisar los datos:

- Existen exactamente **tres clases de conservación** en el catálogo:
  congelado (−25 a −15 °C, 16 medicamentos), refrigerado (2 a 8 °C, 24 medicamentos) y
  ambiente controlado (15 a 25 °C, 27 medicamentos).
- **Los 25 almacenes guardan simultáneamente lotes de las tres clases.**

Un almacén tiene un solo sensor y una sola temperatura. Con las tres clases conviviendo bajo
el mismo techo, **ninguna lectura puede ser correcta para todo el inventario**: si el almacén
está a −20 °C, sus congelados están bien y sus refrigerados y de ambiente están arruinados.

Esto convierte la pregunta habitual —"¿la temperatura está bien?"— en una pregunta mal
planteada. La pregunta correcta es "¿bien para cuál de las tres clases, y qué le está pasando
a las otras dos?".

## La pregunta construida

> Para cada almacén y cada clase de conservación, ¿cuáles fueron sus episodios de exposición
> térmica —entendidos como rachas de lecturas consecutivas fuera del rango—, cuánto duró cada
> racha, qué tan lejos del límite llegó, cuántas unidades de esa clase había expuestas, cómo
> se acumula el tiempo de exposición a lo largo del periodo y cuáles son los episodios más
> severos de cada almacén?

Reúne las tres facetas: duración (8), rachas (9) e inventario en riesgo (10).

## Por qué no se puede resolver con `group by`

Agrupar lecturas consecutivas exige un identificador de racha, y ese identificador no existe
en los datos: hay que fabricarlo. La técnica empleada es **huecos e islas** (*gaps and
islands*), que construye el identificador restando dos numeraciones:

```sql
row_number() over (partition by almacen, clase order by fecha_hora)
- row_number() over (partition by almacen, clase, fuera_de_rango order by fecha_hora)
```

Mientras el estado de cumplimiento no cambia, ambas numeraciones avanzan al mismo paso y su
diferencia permanece constante; cuando el estado cambia, la diferencia salta. Esa constante
es el identificador de la racha.

Un `group by` no puede producirlo: agrupa filas por el **valor** de sus columnas, y aquí la
pertenencia de una fila a un grupo depende de **cuántas filas la preceden en un orden dado**.
Es información posicional, y la posición solo existe dentro de una ventana.

### Window Functions empleadas

| Función | Para qué |
|---|---|
| `row_number()` (dos veces) | Construir las islas de lecturas consecutivas |
| `lag()` | Conocer el instante de la lectura anterior |
| `lead()` | Acotar la ventana de exposición hasta la lectura siguiente |
| `sum() over` | Tiempo de exposición acumulado dentro de cada almacén y clase |
| `rank()` | Ordenar los episodios por severidad dentro de cada almacén |

### Common Table Expressions empleadas

| CTE | Responsabilidad |
|---|---|
| `clases_conservacion` | Deriva las tres clases desde el catálogo, sin codificarlas a mano |
| `inventario_expuesto` | Unidades de cada clase almacenadas en cada almacén |
| `lecturas_evaluadas` | Confronta cada lectura contra cada clase y la sitúa en la serie |
| `islas` | Aplica huecos e islas para identificar las rachas |
| `episodios` | Agrega cada racha en un episodio con sus métricas |

## Resultado obtenido

La función devuelve **140 episodios** sobre los 25 almacenes:

| Clase de conservación | Episodios | De ellos, rachas sostenidas (más de una lectura) |
|---|---|---|
| Congelado | 42 | 16 |
| Refrigerado | 51 | 23 |
| Ambiente controlado | 47 | 21 |

El patrón que emerge confirma la hipótesis: cada almacén opera establemente en **una** clase
de conservación, y para esa clase solo registra picos aislados de una lectura. Para las otras
dos clases registra una única racha continua que cubre casi todo el periodo observado.

Ejemplo concreto — CEDI Bogotá 13:

| Clase | Episodios | Lecturas del episodio mayor | Duración |
|---|---|---|---|
| Congelado | 2 | 1 | 0 h (picos aislados) |
| Refrigerado | 1 | 46 | 4.012 h |
| Ambiente controlado | 1 | 46 | 4.012 h |

El almacén funciona como congelador. Sus 26.907 unidades congeladas están bien cuidadas. Sus
44.856 unidades refrigeradas y sus 32.241 de ambiente controlado llevan casi seis meses fuera
de rango de forma ininterrumpida.

## El insight para el dominio

La empresa no tiene un problema de sensores ni de lecturas anómalas. Tiene un **problema de
asignación de inventario**: está almacenando en la misma bodega productos cuyos rangos de
conservación son mutuamente excluyentes. Ninguna corrección de temperatura resuelve eso,
porque cualquier valor que elija perjudica a dos de las tres clases.

La acción correctiva no es calibrar equipos: es **segregar el inventario por clase de
conservación**, o dotar a cada almacén de cámaras independientes. Un reporte que solo cuente
lecturas fuera de rango jamás habría llevado a esa conclusión.
