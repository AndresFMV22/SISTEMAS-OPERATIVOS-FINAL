# TADB 202620 — Examen 01: Lógica Almacenada en Base de Datos

**Dominio:** Cadena de frío de medicamentos — distribuidora "Distri-Cold"
Universidad Pontificia Bolivariana · Facultad de Ingeniería en Energía, Computación y TIC
Curso: Tópicos Avanzados de Bases de Datos · Periodo 202620
Docente: Juan Darío Rodas M.

## Integrantes

| Nombre completo | ID SIGAA | Motor de base de datos |
|---|---|---|
| Andrés Felipe Martínez | 000549446 | PostgreSQL 18 |
| José Miguel Jaramillo | 000210186 | Microsoft SQL Server 2025 |

Cada integrante es responsable de la implementación completa en su propio motor, así como
de los documentos de abastecimiento de infraestructura y de conexión remota
correspondientes. El diagrama relacional es común a ambas implementaciones.

## Contenido del repositorio

La nomenclatura de los scripts sigue la convención empleada por el docente en los
proyectos de clase: `proyecto_<nombre>_<MOTOR>_<nn>_<contenido>_<AAAAMMDD>.sql`

| Archivo | Descripción |
|---|---|
| `proyecto_cadenaFrio_PGSQL_01_scriptModelo_20260811.sql` | Abastecimiento en Docker, base de datos, usuario y privilegios, esquema `inicial` de staging, esquema `corregido` en 3NF, vistas y rutinas CRUD |
| `proyecto_cadenaFrio_PGSQL_02_borradoModelo_20260811.sql` | Desmonte del modelo para reiniciar desde cero |
| `proyecto_cadenaFrio_PGSQL_03_consultas_20260811.sql` | Consultas de la Etapa 4 (preguntas A, B y C) |
| `proyecto_cadenaFrio_PGSQL_04_funcionCTEWindow_20260811.sql` | Función de la Etapa 5 con CTE y Window Functions, y consulta que la invoca |
| `plan_preguntas_etapa5.md` | Plan previo de la Etapa 5: top 10 de preguntas del dominio y las tres menos exploradas |
| `salidas/` | Resultados de ejecución de las consultas |
| `docs/` | Documentos PDF de infraestructura, conexión e interacción con IA |
| `diagrama_relacional.png` | Diagrama relacional del modelo |

## Verificación

Los scripts fueron ejecutados contra PostgreSQL 18.4 en contenedor Docker, con
`ON_ERROR_STOP=1` y sin errores. Conteos obtenidos tras la carga:

| Tabla | Filas |
|---|---|
| fabricantes | 18 |
| formas_farmaceuticas | 6 |
| ciudades | 10 |
| tipos_almacen | 3 |
| medicamentos | 67 |
| lotes | 259 |
| almacenes | 25 |
| existencias | 1.000 |
| lecturas_temperatura | 1.000 |

Se verificó además que el usuario `cadena_frio_usr` puede consultar y ejecutar rutinas
pero no crear, alterar ni eliminar objetos, ni crear roles o bases de datos.

El modelo se construye en dos esquemas, siguiendo la metodología de clase: `inicial`
recibe el archivo plano tal como llega, con todas las columnas como texto y sin
restricciones; `corregido` contiene el modelo normalizado y se puebla a partir del
primero.

## Origen de los datos

Archivo `datos_cadena_frio.csv`: 1.000 registros, delimitador `;`, codificación UTF-8.
Los datos son artificiales y no representan fabricantes, medicamentos ni almacenes reales.

## Modelo de datos

El CSV llega como una única tabla ancha y desnormalizada. Se descompone en 9 tablas
siguiendo las dependencias funcionales verificadas sobre los datos:

- `medicamento` → fabricante, forma farmacéutica y rango de temperatura
- `lote` → medicamento, fecha de fabricación y fecha de vencimiento
- `almacen` → ciudad y tipo de almacén

Decisión de diseño central: **la existencia de un lote en un almacén y la lectura de
temperatura de ese almacén son hechos independientes.** Aparecen en la misma fila del CSV,
pero las lecturas se toman de forma continua, sin relación con qué lotes hay en la bodega
en ese momento. Modelarlas juntas violaría la 3NF, por lo que viven en tablas separadas:
`existencias` y `lecturas_temperatura`.

## Ejecución

```bash
psql -h <host> -U cadena_frio_owner -d cadena_frio -f 01_modelo_datos.sql
psql -h <host> -U cadena_frio_owner -d cadena_frio -f 02_carga_datos.sql
psql -h <host> -U cadena_frio_owner -d cadena_frio -f 03_consultas.sql
```
