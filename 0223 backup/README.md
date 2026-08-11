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

| Archivo | Descripción |
|---|---|
| `01_modelo_datos.sql` | Creación de roles, esquema, privilegios mínimos, tablas en 3NF, vistas y rutinas CRUD |
| `02_carga_datos.sql` | Carga del CSV a tabla de staging y poblado de las tablas normalizadas |
| `03_consultas.sql` | Consultas de la Etapa 4 (preguntas A, B y C) |
| `04_funcion_cte_window.sql` | Función de la Etapa 5 con CTE y Window Functions, y consulta que la invoca |
| `salidas/` | Resultados de ejecución de las consultas |
| `docs/` | Documentos PDF de infraestructura, conexión e interacción con IA |
| `diagrama_relacional.png` | Diagrama relacional del modelo |

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
