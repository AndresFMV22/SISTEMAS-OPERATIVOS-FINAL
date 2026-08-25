-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)

---Autor: José Miguel Jaramillo
-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- Esto lo corro conectado como cadena_frio_login sobre la base cadena_frio_db.
SELECT
    SUSER_NAME() AS usuario_de_conexion,
    DB_NAME() AS base_de_datos_actual;


-- Etapa 4: las tres consultas de exploración directa que pide el examen.

/*
A.
¿En qué condiciones de temperatura debe conservarse cada medicamento?

Salida esperada: nombre del medicamento, forma farmacéutica,
temperatura mínima, temperatura máxima
*/

SELECT
    m.descripcion       AS medicamento,
    ff.descripcion      AS forma_farmaceutica,
    m.temperatura_min_c AS temperatura_minima,
    m.temperatura_max_c AS temperatura_maxima
FROM corregido.medicamentos m
JOIN corregido.formas_farmaceuticas ff
    ON ff.id = m.forma_farmaceutica_id
ORDER BY m.descripcion;

/*
B.
¿Qué lotes existen de cada medicamento y cuándo vencen?

Salida esperada: nombre del medicamento, código de lote,
fecha de fabricación, fecha de vencimiento
*/

SELECT
    m.descripcion AS medicamento,
    l.codigo      AS lote_codigo,
    l.fecha_fabricacion,
    l.fecha_vencimiento
FROM corregido.medicamentos m
JOIN corregido.lotes l
    ON l.medicamento_id = m.id
ORDER BY m.descripcion, l.fecha_vencimiento;

/*
C.
¿En qué almacenes hay unidades disponibles de cada lote y cuántas?

Salida esperada: nombre del almacén, ciudad, tipo de almacén,
código del lote, nombre del medicamento, cantidad disponible
*/
SELECT
    a.descripcion  AS almacen,
    c.descripcion  AS ciudad,
    ta.descripcion AS tipo_almacen,
    l.codigo       AS lote_codigo,
    m.descripcion  AS medicamento,
    e.cantidad_disponible
FROM corregido.existencias e
JOIN corregido.almacenes a
    ON a.id = e.almacen_id
JOIN corregido.ciudades c
    ON c.id = a.ciudad_id
JOIN corregido.tipos_almacen ta
    ON ta.id = a.tipo_almacen_id
JOIN corregido.lotes l
    ON l.id = e.lote_id
JOIN corregido.medicamentos m
    ON m.id = l.medicamento_id
ORDER BY a.descripcion, l.codigo;
