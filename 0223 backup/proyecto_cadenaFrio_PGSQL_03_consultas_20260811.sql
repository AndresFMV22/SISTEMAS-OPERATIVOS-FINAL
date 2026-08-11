-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
-- Andrés Felipe Martínez - ID SIGAA 000549446
-- Equipo: Andrés Felipe Martínez (000549446) - PostgreSQL 18
--         José Miguel Jaramillo (000210186) - MS SQL Server 2025

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

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
    m.descripcion medicamento,
    ff.descripcion forma_farmaceutica,
    m.temperatura_min_c temperatura_minima,
    m.temperatura_max_c temperatura_maxima
from corregido.medicamentos m
    join corregido.formas_farmaceuticas ff on ff.id = m.forma_farmaceutica_id
order by m.descripcion;

/*
B.
¿Qué lotes existen de cada medicamento y cuándo vencen?

Salida esperada: nombre del medicamento, código de lote,
fecha de fabricación, fecha de vencimiento
*/

select
    m.descripcion medicamento,
    l.codigo lote_codigo,
    l.fecha_fabricacion,
    l.fecha_vencimiento
from corregido.medicamentos m
    join corregido.lotes l on l.medicamento_id = m.id
order by m.descripcion, l.fecha_vencimiento;

/*
C.
¿En qué almacenes hay unidades disponibles de cada lote y cuántas?

Salida esperada: nombre del almacén, ciudad, tipo de almacén,
código del lote, nombre del medicamento, cantidad disponible
*/

select
    a.descripcion almacen,
    c.descripcion ciudad,
    ta.descripcion tipo_almacen,
    l.codigo lote_codigo,
    m.descripcion medicamento,
    e.cantidad_disponible
from corregido.existencias e
    join corregido.almacenes a on a.id = e.almacen_id
    join corregido.ciudades c on c.id = a.ciudad_id
    join corregido.tipos_almacen ta on ta.id = a.tipo_almacen_id
    join corregido.lotes l on l.id = e.lote_id
    join corregido.medicamentos m on m.id = l.medicamento_id
order by a.descripcion, l.codigo;
