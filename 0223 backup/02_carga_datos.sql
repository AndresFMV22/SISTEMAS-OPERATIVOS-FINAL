-- =============================================================================
-- Universidad Pontificia Bolivariana
-- Tópicos Avanzados de Bases de Datos - Periodo 202620
-- Examen No. 1: Lógica Almacenada en Base de Datos
--
-- Autor        : Andrés Felipe Martínez - ID SIGAA 000549446
-- Equipo       : Andrés Felipe Martínez (000549446) - PostgreSQL 18
--                José Miguel Jaramillo  (000210186) - MS SQL Server 2025
-- Motor        : PostgreSQL 18
-- Archivo      : 02_carga_datos.sql
-- Codificación : UTF-8
--
-- Contenido: carga del archivo plano a una tabla de staging y poblado de las
--            tablas normalizadas respetando el orden de dependencias.
-- =============================================================================

SET search_path TO cadena_frio, public;

-- -----------------------------------------------------------------------------
-- 1. TABLA DE STAGING
-- -----------------------------------------------------------------------------
-- Refleja el CSV tal cual llega: una sola tabla ancha, todo como texto. No lleva
-- restricciones a propósito; primero se ingresa el archivo completo y después se
-- reparte hacia el modelo normalizado.

DROP TABLE IF EXISTS stg_cadena_frio;

CREATE TABLE stg_cadena_frio (
    fabricante_nombre               TEXT,
    medicamento_nombre              TEXT,
    forma_farmaceutica              TEXT,
    temperatura_min_c               TEXT,
    temperatura_max_c               TEXT,
    lote_codigo                     TEXT,
    lote_fecha_fabricacion          TEXT,
    lote_fecha_vencimiento          TEXT,
    almacen_nombre                  TEXT,
    almacen_ciudad                  TEXT,
    almacen_tipo                    TEXT,
    existencia_cantidad_disponible  TEXT,
    lectura_fecha_hora              TEXT,
    lectura_temperatura_c           TEXT
);

-- El archivo usa punto y coma como delimitador y viene en UTF-8 con encabezado.
-- \copy se ejecuta del lado del cliente: la ruta es relativa al directorio desde
-- donde se invoca psql, y no requiere que el archivo esté en el servidor.
\copy stg_cadena_frio FROM 'datos_cadena_frio/datos_cadena_frio.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')

-- -----------------------------------------------------------------------------
-- 2. CATÁLOGOS
-- -----------------------------------------------------------------------------

INSERT INTO fabricantes (nombre)
SELECT DISTINCT TRIM(fabricante_nombre)
FROM   stg_cadena_frio
ORDER  BY 1;

INSERT INTO formas_farmaceuticas (descripcion)
SELECT DISTINCT TRIM(forma_farmaceutica)
FROM   stg_cadena_frio
ORDER  BY 1;

INSERT INTO ciudades (nombre)
SELECT DISTINCT TRIM(almacen_ciudad)
FROM   stg_cadena_frio
ORDER  BY 1;

INSERT INTO tipos_almacen (descripcion)
SELECT DISTINCT TRIM(almacen_tipo)
FROM   stg_cadena_frio
ORDER  BY 1;

-- -----------------------------------------------------------------------------
-- 3. ENTIDADES PRINCIPALES
-- -----------------------------------------------------------------------------
-- El DISTINCT sobre todas las columnas del grupo es seguro porque las
-- dependencias funcionales se verificaron previamente sobre el archivo: ningún
-- medicamento aparece con dos fabricantes, formas o rangos distintos.

INSERT INTO medicamentos (nombre, fabricante_id, forma_farmaceutica_id,
                          temperatura_min_c, temperatura_max_c)
SELECT DISTINCT
       TRIM(s.medicamento_nombre),
       f.id,
       ff.id,
       s.temperatura_min_c::NUMERIC(5,2),
       s.temperatura_max_c::NUMERIC(5,2)
FROM   stg_cadena_frio s
       JOIN fabricantes          f  ON f.nombre       = TRIM(s.fabricante_nombre)
       JOIN formas_farmaceuticas ff ON ff.descripcion = TRIM(s.forma_farmaceutica);

INSERT INTO lotes (codigo, medicamento_id, fecha_fabricacion, fecha_vencimiento)
SELECT DISTINCT
       TRIM(s.lote_codigo),
       m.id,
       s.lote_fecha_fabricacion::DATE,
       s.lote_fecha_vencimiento::DATE
FROM   stg_cadena_frio s
       JOIN medicamentos m ON m.nombre = TRIM(s.medicamento_nombre);

INSERT INTO almacenes (nombre, ciudad_id, tipo_almacen_id)
SELECT DISTINCT
       TRIM(s.almacen_nombre),
       c.id,
       ta.id
FROM   stg_cadena_frio s
       JOIN ciudades      c  ON c.nombre       = TRIM(s.almacen_ciudad)
       JOIN tipos_almacen ta ON ta.descripcion = TRIM(s.almacen_tipo);

-- -----------------------------------------------------------------------------
-- 4. HECHOS
-- -----------------------------------------------------------------------------

INSERT INTO existencias (lote_id, almacen_id, cantidad_disponible)
SELECT l.id,
       a.id,
       s.existencia_cantidad_disponible::INTEGER
FROM   stg_cadena_frio s
       JOIN lotes     l ON l.codigo = TRIM(s.lote_codigo)
       JOIN almacenes a ON a.nombre = TRIM(s.almacen_nombre);

INSERT INTO lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
SELECT a.id,
       s.lectura_fecha_hora::TIMESTAMP,
       s.lectura_temperatura_c::NUMERIC(5,2)
FROM   stg_cadena_frio s
       JOIN almacenes a ON a.nombre = TRIM(s.almacen_nombre);

-- -----------------------------------------------------------------------------
-- 5. VERIFICACIÓN DE LA CARGA
-- -----------------------------------------------------------------------------
-- Los conteos esperados provienen del análisis previo del archivo. Si alguno no
-- coincide, la carga se detiene con error en lugar de dejar el modelo a medias.

DO $$
DECLARE
    v_fabricantes INTEGER;
    v_formas      INTEGER;
    v_ciudades    INTEGER;
    v_tipos       INTEGER;
    v_medicamentos INTEGER;
    v_lotes       INTEGER;
    v_almacenes   INTEGER;
    v_existencias INTEGER;
    v_lecturas    INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_fabricantes  FROM fabricantes;
    SELECT COUNT(*) INTO v_formas       FROM formas_farmaceuticas;
    SELECT COUNT(*) INTO v_ciudades     FROM ciudades;
    SELECT COUNT(*) INTO v_tipos        FROM tipos_almacen;
    SELECT COUNT(*) INTO v_medicamentos FROM medicamentos;
    SELECT COUNT(*) INTO v_lotes        FROM lotes;
    SELECT COUNT(*) INTO v_almacenes    FROM almacenes;
    SELECT COUNT(*) INTO v_existencias  FROM existencias;
    SELECT COUNT(*) INTO v_lecturas     FROM lecturas_temperatura;

    ASSERT v_fabricantes  =   18, 'fabricantes: se esperaban 18, hay '   || v_fabricantes;
    ASSERT v_formas       =    6, 'formas: se esperaban 6, hay '         || v_formas;
    ASSERT v_ciudades     =   10, 'ciudades: se esperaban 10, hay '      || v_ciudades;
    ASSERT v_tipos        =    3, 'tipos de almacén: se esperaban 3, hay '|| v_tipos;
    ASSERT v_medicamentos =   67, 'medicamentos: se esperaban 67, hay '  || v_medicamentos;
    ASSERT v_lotes        =  259, 'lotes: se esperaban 259, hay '        || v_lotes;
    ASSERT v_almacenes    =   25, 'almacenes: se esperaban 25, hay '     || v_almacenes;
    ASSERT v_existencias  = 1000, 'existencias: se esperaban 1000, hay ' || v_existencias;
    ASSERT v_lecturas     = 1000, 'lecturas: se esperaban 1000, hay '    || v_lecturas;

    RAISE NOTICE 'Carga verificada correctamente.';
    RAISE NOTICE '  fabricantes=%  formas=%  ciudades=%  tipos=%',
                 v_fabricantes, v_formas, v_ciudades, v_tipos;
    RAISE NOTICE '  medicamentos=%  lotes=%  almacenes=%',
                 v_medicamentos, v_lotes, v_almacenes;
    RAISE NOTICE '  existencias=%  lecturas=%', v_existencias, v_lecturas;
END;
$$;

-- La tabla de staging ya cumplió su función.
DROP TABLE stg_cadena_frio;

-- =============================================================================
-- Fin del script 02_carga_datos.sql
-- =============================================================================
