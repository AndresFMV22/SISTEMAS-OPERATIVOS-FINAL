-- =============================================================================
-- Universidad Pontificia Bolivariana
-- Tópicos Avanzados de Bases de Datos - Periodo 202620
-- Examen No. 1: Lógica Almacenada en Base de Datos
-- Dominio: Cadena de frío de medicamentos - "Distri-Cold"
--
-- Autor        : Andrés Felipe Martínez - ID SIGAA 000549446
-- Equipo       : Andrés Felipe Martínez (000549446) - PostgreSQL 18
--                José Miguel Jaramillo  (000210186) - MS SQL Server 2025
-- Motor        : PostgreSQL 18
-- Archivo      : 01_modelo_datos.sql
-- Codificación : UTF-8
--
-- Contenido: creación de roles, esquema, privilegios mínimos, tablas en 3NF,
--            índices, vistas y rutinas de apoyo a las operaciones CRUD.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ROLES Y PRIVILEGIOS MÍNIMOS
-- -----------------------------------------------------------------------------
-- Se separan dos roles: uno propietario del modelo (DDL) y uno de aplicación
-- que solo manipula datos. El rol de aplicación nunca puede alterar la
-- estructura ni crear objetos: ese es el principio de privilegio mínimo.
--
-- Ejecutar esta sección conectado como superusuario (postgres).
-- Reemplazar las contraseñas antes de usar en un entorno real.

CREATE ROLE cadena_frio_owner WITH LOGIN PASSWORD 'CambiarEstaClave_Owner' NOSUPERUSER NOCREATEROLE;
CREATE ROLE cadena_frio_app   WITH LOGIN PASSWORD 'CambiarEstaClave_App'   NOSUPERUSER NOCREATEDB NOCREATEROLE;

CREATE DATABASE cadena_frio WITH OWNER = cadena_frio_owner ENCODING = 'UTF8';

-- Nadie más que el propietario crea objetos en el esquema público.
REVOKE ALL ON DATABASE cadena_frio FROM PUBLIC;
GRANT  CONNECT ON DATABASE cadena_frio TO cadena_frio_owner, cadena_frio_app;

-- -----------------------------------------------------------------------------
-- A partir de aquí: conectarse a la base cadena_frio como cadena_frio_owner
--   \connect cadena_frio cadena_frio_owner
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS cadena_frio AUTHORIZATION cadena_frio_owner;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
SET search_path TO cadena_frio, public;

-- El rol de aplicación puede ver el esquema y manipular filas, nada más.
GRANT USAGE ON SCHEMA cadena_frio TO cadena_frio_app;

-- -----------------------------------------------------------------------------
-- 2. CATÁLOGOS
-- -----------------------------------------------------------------------------
-- Cada catálogo aísla un atributo que se repetía en el CSV original y que
-- depende únicamente de su propia clave. Las claves subrogadas se generan con
-- IDENTITY, que internamente crea y administra una secuencia por tabla.

CREATE TABLE fabricantes (
    id     INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    CONSTRAINT uk_fabricantes_nombre UNIQUE (nombre)
);

CREATE TABLE formas_farmaceuticas (
    id          INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descripcion VARCHAR(50) NOT NULL,
    CONSTRAINT uk_formas_farmaceuticas_descripcion UNIQUE (descripcion)
);

CREATE TABLE ciudades (
    id     INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    CONSTRAINT uk_ciudades_nombre UNIQUE (nombre)
);

CREATE TABLE tipos_almacen (
    id          INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descripcion VARCHAR(50) NOT NULL,
    CONSTRAINT uk_tipos_almacen_descripcion UNIQUE (descripcion)
);

-- -----------------------------------------------------------------------------
-- 3. ENTIDADES PRINCIPALES
-- -----------------------------------------------------------------------------

-- El rango de temperatura es un atributo del medicamento, no del lote ni de la
-- lectura: en los 1.000 registros del CSV, cada medicamento conserva siempre el
-- mismo par (mínima, máxima). Ubicarlo aquí elimina esa redundancia.
CREATE TABLE medicamentos (
    id                     INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre                 VARCHAR(150) NOT NULL,
    fabricante_id          INTEGER      NOT NULL,
    forma_farmaceutica_id  INTEGER      NOT NULL,
    temperatura_min_c      NUMERIC(5,2) NOT NULL,
    temperatura_max_c      NUMERIC(5,2) NOT NULL,
    CONSTRAINT uk_medicamentos_nombre UNIQUE (nombre),
    CONSTRAINT fk_medicamentos_fabricante
        FOREIGN KEY (fabricante_id) REFERENCES fabricantes (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_medicamentos_forma_farmaceutica
        FOREIGN KEY (forma_farmaceutica_id) REFERENCES formas_farmaceuticas (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_medicamentos_rango_temperatura
        CHECK (temperatura_min_c < temperatura_max_c)
);

-- Un lote pertenece a un solo medicamento (verificado sobre los datos: ningún
-- código de lote aparece asociado a dos medicamentos distintos).
CREATE TABLE lotes (
    id                 INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo             VARCHAR(20) NOT NULL,
    medicamento_id     INTEGER     NOT NULL,
    fecha_fabricacion  DATE        NOT NULL,
    fecha_vencimiento  DATE        NOT NULL,
    CONSTRAINT uk_lotes_codigo UNIQUE (codigo),
    CONSTRAINT fk_lotes_medicamento
        FOREIGN KEY (medicamento_id) REFERENCES medicamentos (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_lotes_vigencia
        CHECK (fecha_vencimiento > fecha_fabricacion)
);

CREATE TABLE almacenes (
    id              INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(120) NOT NULL,
    ciudad_id       INTEGER      NOT NULL,
    tipo_almacen_id INTEGER      NOT NULL,
    CONSTRAINT uk_almacenes_nombre UNIQUE (nombre),
    CONSTRAINT fk_almacenes_ciudad
        FOREIGN KEY (ciudad_id) REFERENCES ciudades (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_almacenes_tipo
        FOREIGN KEY (tipo_almacen_id) REFERENCES tipos_almacen (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- 4. HECHOS
-- -----------------------------------------------------------------------------
-- Las dos tablas siguientes son el corazón de la decisión de diseño. En el CSV
-- la existencia y la lectura de temperatura comparten fila, pero son hechos
-- independientes: las lecturas se registran de forma continua, sin relación con
-- qué lotes se encuentran en la bodega en ese instante. Mantenerlas en una sola
-- tabla introduciría una dependencia inexistente y rompería la 3NF.

-- Un mismo lote puede repartirse entre varios almacenes y un mismo almacén
-- puede alojar decenas de lotes: la relación es de muchos a muchos y su clave
-- primaria es la pareja (lote, almacén).
CREATE TABLE existencias (
    lote_id             INTEGER NOT NULL,
    almacen_id          INTEGER NOT NULL,
    cantidad_disponible INTEGER NOT NULL,
    CONSTRAINT pk_existencias PRIMARY KEY (lote_id, almacen_id),
    CONSTRAINT fk_existencias_lote
        FOREIGN KEY (lote_id) REFERENCES lotes (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_existencias_almacen
        FOREIGN KEY (almacen_id) REFERENCES almacenes (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_existencias_cantidad
        CHECK (cantidad_disponible > 0)
);

-- Serie temporal por almacén. La restricción única evita dos lecturas del mismo
-- almacén en el mismo instante y es además el índice natural para recorrer la
-- serie en orden cronológico con Window Functions.
CREATE TABLE lecturas_temperatura (
    id            INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    almacen_id    INTEGER      NOT NULL,
    fecha_hora    TIMESTAMP    NOT NULL,
    temperatura_c NUMERIC(5,2) NOT NULL,
    CONSTRAINT uk_lecturas_almacen_fecha UNIQUE (almacen_id, fecha_hora),
    CONSTRAINT fk_lecturas_almacen
        FOREIGN KEY (almacen_id) REFERENCES almacenes (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- 5. ÍNDICES DE APOYO
-- -----------------------------------------------------------------------------
-- PostgreSQL crea índice automáticamente para las claves primarias y únicas,
-- pero no para las foráneas. Estos son los recorridos que usan las consultas.

CREATE INDEX ix_medicamentos_fabricante ON medicamentos (fabricante_id);
CREATE INDEX ix_medicamentos_forma      ON medicamentos (forma_farmaceutica_id);
CREATE INDEX ix_lotes_medicamento       ON lotes (medicamento_id);
CREATE INDEX ix_lotes_vencimiento       ON lotes (fecha_vencimiento);
CREATE INDEX ix_almacenes_ciudad        ON almacenes (ciudad_id);
CREATE INDEX ix_almacenes_tipo          ON almacenes (tipo_almacen_id);
CREATE INDEX ix_existencias_almacen     ON existencias (almacen_id);

-- -----------------------------------------------------------------------------
-- 6. VISTAS
-- -----------------------------------------------------------------------------
-- Resuelven las reuniones recurrentes entre las tablas normalizadas y devuelven
-- el modelo a una forma legible para el usuario final.

CREATE OR REPLACE VIEW v_medicamentos_detalle AS
SELECT m.id                AS medicamento_id,
       m.nombre            AS medicamento,
       ff.descripcion      AS forma_farmaceutica,
       f.nombre            AS fabricante,
       m.temperatura_min_c,
       m.temperatura_max_c
FROM   medicamentos m
       JOIN formas_farmaceuticas ff ON ff.id = m.forma_farmaceutica_id
       JOIN fabricantes          f  ON f.id  = m.fabricante_id;

COMMENT ON VIEW v_medicamentos_detalle IS
    'Medicamento con su fabricante, forma farmacéutica y rango de conservación.';

CREATE OR REPLACE VIEW v_lotes_detalle AS
SELECT l.id               AS lote_id,
       l.codigo           AS lote_codigo,
       m.id               AS medicamento_id,
       m.nombre           AS medicamento,
       l.fecha_fabricacion,
       l.fecha_vencimiento
FROM   lotes l
       JOIN medicamentos m ON m.id = l.medicamento_id;

COMMENT ON VIEW v_lotes_detalle IS
    'Lote con el medicamento al que pertenece y sus fechas de vigencia.';

CREATE OR REPLACE VIEW v_almacenes_detalle AS
SELECT a.id          AS almacen_id,
       a.nombre      AS almacen,
       c.nombre      AS ciudad,
       ta.descripcion AS tipo_almacen
FROM   almacenes a
       JOIN ciudades      c  ON c.id  = a.ciudad_id
       JOIN tipos_almacen ta ON ta.id = a.tipo_almacen_id;

COMMENT ON VIEW v_almacenes_detalle IS
    'Almacén con su ciudad y tipo.';

-- -----------------------------------------------------------------------------
-- 7. RUTINAS DE APOYO A LAS OPERACIONES CRUD
-- -----------------------------------------------------------------------------
-- Encapsulan las escrituras habituales sobre el modelo y resuelven por nombre
-- las claves subrogadas, de modo que quien consume el modelo no necesita
-- conocer los identificadores internos.

-- CREATE / UPDATE de una existencia. Si la pareja (lote, almacén) ya existe,
-- actualiza la cantidad; si no, la inserta.
CREATE OR REPLACE PROCEDURE sp_registrar_existencia(
    p_lote_codigo    VARCHAR,
    p_almacen_nombre VARCHAR,
    p_cantidad       INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_lote_id    INTEGER;
    v_almacen_id INTEGER;
BEGIN
    SELECT id INTO v_lote_id    FROM lotes     WHERE codigo = p_lote_codigo;
    SELECT id INTO v_almacen_id FROM almacenes WHERE nombre = p_almacen_nombre;

    IF v_lote_id IS NULL THEN
        RAISE EXCEPTION 'No existe el lote con código %', p_lote_codigo;
    END IF;
    IF v_almacen_id IS NULL THEN
        RAISE EXCEPTION 'No existe el almacén %', p_almacen_nombre;
    END IF;

    INSERT INTO existencias (lote_id, almacen_id, cantidad_disponible)
    VALUES (v_lote_id, v_almacen_id, p_cantidad)
    ON CONFLICT (lote_id, almacen_id)
    DO UPDATE SET cantidad_disponible = EXCLUDED.cantidad_disponible;
END;
$$;

-- CREATE de una lectura de temperatura.
CREATE OR REPLACE FUNCTION fn_registrar_lectura(
    p_almacen_nombre VARCHAR,
    p_fecha_hora     TIMESTAMP,
    p_temperatura    NUMERIC
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_almacen_id INTEGER;
    v_lectura_id INTEGER;
BEGIN
    SELECT id INTO v_almacen_id FROM almacenes WHERE nombre = p_almacen_nombre;

    IF v_almacen_id IS NULL THEN
        RAISE EXCEPTION 'No existe el almacén %', p_almacen_nombre;
    END IF;

    INSERT INTO lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
    VALUES (v_almacen_id, p_fecha_hora, p_temperatura)
    RETURNING id INTO v_lectura_id;

    RETURN v_lectura_id;
END;
$$;

-- DELETE de una existencia agotada.
CREATE OR REPLACE PROCEDURE sp_eliminar_existencia(
    p_lote_codigo    VARCHAR,
    p_almacen_nombre VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM existencias e
     USING lotes l, almacenes a
     WHERE e.lote_id    = l.id
       AND e.almacen_id = a.id
       AND l.codigo     = p_lote_codigo
       AND a.nombre     = p_almacen_nombre;

    IF NOT FOUND THEN
        RAISE NOTICE 'No había existencia del lote % en el almacén %',
                     p_lote_codigo, p_almacen_nombre;
    END IF;
END;
$$;

-- READ: cantidad total disponible de un lote sumando todos los almacenes.
CREATE OR REPLACE FUNCTION fn_disponible_por_lote(p_lote_codigo VARCHAR)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(e.cantidad_disponible), 0)::INTEGER
    FROM   existencias e
           JOIN lotes l ON l.id = e.lote_id
    WHERE  l.codigo = p_lote_codigo;
$$;

-- -----------------------------------------------------------------------------
-- 8. PRIVILEGIOS SOBRE LOS OBJETOS CREADOS
-- -----------------------------------------------------------------------------
-- El rol de aplicación manipula filas y ejecuta las rutinas, pero no puede
-- crear, alterar ni eliminar objetos. Sin permisos sobre las secuencias de las
-- columnas IDENTITY no podría insertar, por eso se otorgan explícitamente.

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA cadena_frio TO cadena_frio_app;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA cadena_frio TO cadena_frio_app;
GRANT EXECUTE                        ON ALL ROUTINES  IN SCHEMA cadena_frio TO cadena_frio_app;

-- Mismos privilegios para los objetos que se creen más adelante.
ALTER DEFAULT PRIVILEGES IN SCHEMA cadena_frio
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cadena_frio_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA cadena_frio
    GRANT USAGE, SELECT ON SEQUENCES TO cadena_frio_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA cadena_frio
    GRANT EXECUTE ON ROUTINES TO cadena_frio_app;

-- =============================================================================
-- Fin del script 01_modelo_datos.sql
-- =============================================================================
