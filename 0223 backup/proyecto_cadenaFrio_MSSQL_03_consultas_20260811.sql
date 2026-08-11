-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- Ejecutar conectado como cadena_frio_login sobre la base cadena_frio_db.
select suser_name() as usuario_de_conexion, db_name() as base_de_datos_actual;
go

-- ***********************************
-- Etapa 4 - Solución de consultas
-- ***********************************

/*
A.
¿En qué condiciones de temperatura debe conservarse cada medicamento?

Salida esperada: nombre del medicamento, forma farmacéutica,
temperatura mínima, temperatura máxima
*/

select
    m.descripcion       as medicamento,
    ff.descripcion      as forma_farmaceutica,
    m.temperatura_min_c as temperatura_minima,
    m.temperatura_max_c as temperatura_maxima
from corregido.medicamentos m
    join corregido.formas_farmaceuticas ff on ff.id = m.forma_farmaceutica_id
order by m.descripcion;
go

/*
B.
¿Qué lotes existen de cada medicamento y cuándo vencen?

Salida esperada: nombre del medicamento, código de lote,
fecha de fabricación, fecha de vencimiento
*/

select
    m.descripcion as medicamento,
    l.codigo      as lote_codigo,
    l.fecha_fabricacion,
    l.fecha_vencimiento
from corregido.medicamentos m
    join corregido.lotes l on l.medicamento_id = m.id
order by m.descripcion, l.fecha_vencimiento;
go

/*
C.
¿En qué almacenes hay unidades disponibles de cada lote y cuántas?

Salida esperada: nombre del almacén, ciudad, tipo de almacén,
código del lote, nombre del medicamento, cantidad disponible
*/

select
    a.descripcion  as almacen,
    c.descripcion  as ciudad,
    ta.descripcion as tipo_almacen,
    l.codigo       as lote_codigo,
    m.descripcion  as medicamento,
    e.cantidad_disponible
from corregido.existencias e
    join corregido.almacenes a on a.id = e.almacen_id
    join corregido.ciudades c on c.id = a.ciudad_id
    join corregido.tipos_almacen ta on ta.id = a.tipo_almacen_id
    join corregido.lotes l on l.id = e.lote_id
    join corregido.medicamentos m on m.id = l.medicamento_id
order by a.descripcion, l.codigo;
go
