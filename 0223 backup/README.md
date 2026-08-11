# TADB 202620 — Examen 01: Lógica Almacenada en Base de Datos

**Dominio:** Cadena de frío de medicamentos — distribuidora "Distri-Cold"
Universidad Pontificia Bolivariana · Facultad de Ingeniería en Energía, Computación y TIC
Curso: Tópicos Avanzados de Bases de Datos · Periodo 202620
Docente: Juan Darío Rodas M.

## Integrantes

| Nombre completo | ID SIGAA | Motor de base de datos | Infraestructura |
|---|---|---|---|
| Andrés Felipe Martínez | 000549446 | PostgreSQL 18 | Microsoft Azure (nube) |
| José Miguel Jaramillo | 000210186 | Microsoft SQL Server 2025 | Docker local |

Los dos integrantes implementan **el mismo modelo de datos**: las mismas nueve tablas, las
mismas columnas, la misma nomenclatura y las mismas restricciones. Lo único que cambia es
el dialecto de SQL y el motor. Por eso el diagrama relacional es uno solo y sirve para las
dos implementaciones.

Andrés despliega en **Microsoft Azure**, con lo que el equipo opta a la bonificación de
despliegue en nube; la evidencia de conexión cifrada está documentada en la guía de
infraestructura.

## Contenido del repositorio

La nomenclatura de los scripts sigue la convención empleada por el docente en los
proyectos de clase: `proyecto_<nombre>_<MOTOR>_<nn>_<contenido>_<AAAAMMDD>.sql`

### Implementación en PostgreSQL 18 — Andrés Felipe Martínez (000549446)

| Archivo | Descripción |
|---|---|
| `proyecto_cadenaFrio_PGSQL_01_scriptModelo_20260811.sql` | Abastecimiento, base de datos, usuario de mínimos privilegios, esquemas, tablas, vistas y rutinas CRUD |
| `proyecto_cadenaFrio_PGSQL_02_borradoModelo_20260811.sql` | Desmonte completo del modelo |
| `proyecto_cadenaFrio_PGSQL_03_consultas_20260811.sql` | Consultas de la Etapa 4 |
| `proyecto_cadenaFrio_PGSQL_04_funcionCTEWindow_20260811.sql` | Función de la Etapa 5 con CTE y Window Functions |

### Implementación en SQL Server 2025 — José Miguel Jaramillo (000210186)

| Archivo | Descripción |
|---|---|
| `proyecto_cadenaFrio_MSSQL_01_scriptModelo_20260811.sql` | Equivalente T-SQL del modelo, con las mismas tablas y nomenclatura |
| `proyecto_cadenaFrio_MSSQL_02_borradoModelo_20260811.sql` | Desmonte completo del modelo |
| `proyecto_cadenaFrio_MSSQL_03_consultas_20260811.sql` | Consultas de la Etapa 4 |
| `proyecto_cadenaFrio_MSSQL_04_funcionCTEWindow_20260811.sql` | Función de la Etapa 5 como función con valores de tabla |

### Documentos comunes

| Archivo | Descripción |
|---|---|
| `diagrama_relacional.png` | Diagrama relacional del modelo, fondo blanco. Común a las dos implementaciones |
| `diagrama_relacional.drawio` | Fuente editable del diagrama |
| `plan_preguntas_etapa5.md` | Plan previo de la Etapa 5: top 10 de preguntas del dominio y las tres menos exploradas |
| `docs/guia_infraestructura_y_conexion.docx` | Guía paso a paso de las Etapas 1 y 2 para ambos motores |
| `salidas/` | Resultados de ejecución de las consultas |
| `datos_cadena_frio/` | Archivo de datos de origen |

## Origen de los datos

Archivo `datos_cadena_frio.csv`: 1.000 registros, delimitador `;`, codificación UTF-8.
Los datos son artificiales y no representan fabricantes, medicamentos ni almacenes reales.

## Modelo de datos

El CSV llega como una única tabla ancha y desnormalizada. Se descompone en nueve tablas
siguiendo las dependencias funcionales verificadas sobre los datos:

- `medicamento` → fabricante, forma farmacéutica y rango de temperatura
- `lote` → medicamento, fecha de fabricación y fecha de vencimiento
- `almacen` → ciudad y tipo de almacén

Decisión de diseño central: **la existencia de un lote en un almacén y la lectura de
temperatura de ese almacén son hechos independientes.** Aparecen en la misma fila del CSV,
pero las lecturas se toman de forma continua, sin relación con qué lotes hay en la bodega
en ese momento. Modelarlas juntas violaría la 3NF, por lo que viven en tablas separadas:
`existencias` y `lecturas_temperatura`.

El modelo se construye en dos esquemas, siguiendo la metodología de clase: `inicial`
recibe el archivo plano tal como llega, con todas las columnas como texto y sin
restricciones; `corregido` contiene el modelo normalizado y se puebla a partir del primero.

## Privilegios mínimos

El usuario administrador del motor (`postgres` en PostgreSQL, `sa` en SQL Server) se emplea
únicamente para las dos acciones que ningún otro rol puede realizar: crear la base de datos
y crear el usuario de trabajo. A partir de ahí, **todo el modelo se crea y se opera con un
usuario sin atributos administrativos** (`cadena_frio_usr`).

Los scripts del modelo incluyen cinco bloques de evidencia:

1. La sesión no usa el usuario administrador ni la base de datos predeterminada del motor
2. El rol no es superusuario y no puede crear bases de datos ni roles
3. El propietario de las diez tablas es el usuario de mínimos privilegios
4. Las sentencias administrativas fallan con error de permiso denegado
5. Ningún objeto se creó fuera de la base de datos de trabajo

## Verificación

Los scripts de PostgreSQL fueron ejecutados contra PostgreSQL 18.4 en contenedor Docker,
con `ON_ERROR_STOP=1` y sin errores. Conteos obtenidos tras la carga:

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
