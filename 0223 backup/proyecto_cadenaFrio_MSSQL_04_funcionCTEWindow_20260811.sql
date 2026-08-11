-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- *****************************************************************
-- Etapa 5 - Función con Common Table Expressions y Window Functions
-- *****************************************************************

/*
================================================================
La pregunta en lenguaje natural
================================================================

Cada almacén de la red guarda al mismo tiempo medicamentos de las tres clases
de conservación que maneja la empresa: congelados (-25 a -15 °C), refrigerados
(2 a 8 °C) y de ambiente controlado (15 a 25 °C). Un único sensor no puede
estar simultáneamente en lo correcto para las tres, de modo que toda lectura
deja necesariamente una parte del inventario fuera de su rango.

La pregunta es entonces:

    Para cada almacén y cada clase de conservación, ¿cuáles fueron sus
    episodios de exposición térmica -entendidos como rachas de lecturas
    consecutivas fuera del rango-, cuánto duró cada racha, qué tan lejos
    del límite llegó, cuántas unidades de esa clase había expuestas, cómo
    se acumula el tiempo de exposición a lo largo del periodo y cuáles son
    los episodios más severos de cada almacén?

El plan previo que llevó a esta pregunta está en el documento
"plan_preguntas_etapa5.md" que acompaña esta entrega.

================================================================
Por qué requiere Window Functions y no se puede resolver con group by
================================================================

Identificar una "racha de lecturas consecutivas fuera de rango" exige comparar
cada fila con su vecina en un orden determinado. La técnica empleada es la de
huecos e islas (gaps and islands): la diferencia entre dos numeraciones
row_number(), una sobre toda la serie del almacén y otra sobre las filas que
comparten el estado de cumplimiento, produce un identificador constante para
cada racha. No existe forma de derivar ese identificador con un group by,
porque el grupo al que pertenece una fila depende de la posición de las filas
anteriores, no de sus valores.

Window functions utilizadas:
  - row_number()  dos veces, para construir las islas de lecturas consecutivas
  - lag()         para conocer el instante de la lectura anterior
  - lead()        para acotar la ventana de exposición hasta la lectura siguiente
  - sum() over    para el tiempo de exposición acumulado dentro de cada almacén
  - rank()        para ordenar los episodios por severidad dentro de cada almacén

La sintaxis de estas funciones es idéntica en PostgreSQL y en SQL Server, de
modo que la implementación es equivalente en ambos motores.
*/

-- ================================================================
-- El código fuente de la función
-- ================================================================

create or alter function corregido.f_episodios_riesgo_termico
(
    @p_clase_conservacion nvarchar(50) = null
)
returns table
as
return
(
    with clases_conservacion as (
        -- CTE 1: las clases de conservación que existen en el catálogo de
        -- medicamentos. Se derivan de los datos y no se codifican a mano.
        select distinct
            m.temperatura_min_c,
            m.temperatura_max_c,
            case
                when m.temperatura_max_c <= 0 then 'Congelado'
                when m.temperatura_max_c <= 8 then 'Refrigerado'
                else 'Ambiente controlado'
            end as clase
        from corregido.medicamentos m
    ),
    inventario_expuesto as (
        -- CTE 2: unidades almacenadas de cada clase en cada almacén. Es el
        -- inventario que queda en riesgo cuando esa clase sale de rango.
        select
            e.almacen_id,
            cc.clase,
            sum(e.cantidad_disponible) as unidades
        from corregido.existencias e
            join corregido.lotes l on l.id = e.lote_id
            join corregido.medicamentos m on m.id = l.medicamento_id
            join clases_conservacion cc
                on cc.temperatura_min_c = m.temperatura_min_c
               and cc.temperatura_max_c = m.temperatura_max_c
        group by e.almacen_id, cc.clase
    ),
    lecturas_evaluadas as (
        -- CTE 3: cada lectura se confronta contra cada clase de conservación.
        -- lag y lead sitúan la lectura dentro de la serie del almacén.
        select
            lt.almacen_id,
            cc.clase,
            lt.fecha_hora,
            lt.temperatura_c,
            cc.temperatura_min_c,
            cc.temperatura_max_c,
            case
                when lt.temperatura_c < cc.temperatura_min_c
                  or lt.temperatura_c > cc.temperatura_max_c then 1
                else 0
            end as fuera_de_rango,
            lag(lt.fecha_hora) over (
                partition by lt.almacen_id, cc.clase order by lt.fecha_hora
            ) as lectura_anterior,
            lead(lt.fecha_hora) over (
                partition by lt.almacen_id, cc.clase order by lt.fecha_hora
            ) as lectura_siguiente
        from corregido.lecturas_temperatura lt
            cross join clases_conservacion cc
        where @p_clase_conservacion is null
           or cc.clase = @p_clase_conservacion
    ),
    islas as (
        -- CTE 4: huecos e islas. La diferencia entre las dos numeraciones es
        -- constante mientras el estado de cumplimiento no cambie, de modo que
        -- identifica cada racha de lecturas consecutivas.
        select
            le.almacen_id,
            le.clase,
            le.fecha_hora,
            le.temperatura_c,
            le.temperatura_min_c,
            le.temperatura_max_c,
            le.fuera_de_rango,
            le.lectura_siguiente,
            row_number() over (
                partition by le.almacen_id, le.clase order by le.fecha_hora
            )
            - row_number() over (
                partition by le.almacen_id, le.clase, le.fuera_de_rango
                order by le.fecha_hora
            ) as isla
        from lecturas_evaluadas le
    ),
    episodios as (
        -- CTE 5: se agrega cada isla que corresponda a una racha fuera de rango.
        select
            i.almacen_id,
            i.clase,
            i.isla,
            min(i.fecha_hora) as fecha_inicio,
            max(i.fecha_hora) as fecha_fin,
            count(*) as lecturas,
            cast(datediff(second, min(i.fecha_hora), max(i.fecha_hora)) / 3600.0
                 as decimal(12,2)) as duracion_horas,
            cast(datediff(second, min(i.fecha_hora),
                          coalesce(max(i.lectura_siguiente), max(i.fecha_hora))) / 3600.0
                 as decimal(12,2)) as ventana_exposicion_horas,
            max(greatest(i.temperatura_min_c - i.temperatura_c,
                         i.temperatura_c - i.temperatura_max_c)) as desviacion_maxima_c
        from islas i
        where i.fuera_de_rango = 1
        group by i.almacen_id, i.clase, i.isla
    )
    -- Consulta final: se numeran los episodios, se acumula el tiempo de
    -- exposición y se ordenan por severidad dentro de cada almacén.
    select
        a.descripcion as almacen,
        c.descripcion as ciudad,
        ep.clase      as clase_conservacion,
        row_number() over (
            partition by ep.almacen_id, ep.clase order by ep.fecha_inicio
        ) as episodio,
        ep.fecha_inicio,
        ep.fecha_fin,
        ep.lecturas,
        ep.duracion_horas,
        ep.ventana_exposicion_horas,
        ep.desviacion_maxima_c,
        coalesce(ie.unidades, 0) as unidades_en_riesgo,
        cast(sum(ep.duracion_horas) over (
                 partition by ep.almacen_id, ep.clase
                 order by ep.fecha_inicio
                 rows between unbounded preceding and current row
             ) as decimal(12,2)) as horas_acumuladas,
        rank() over (
            partition by ep.almacen_id
            order by ep.duracion_horas desc, ep.desviacion_maxima_c desc
        ) as severidad_en_almacen
    from episodios ep
        join corregido.almacenes a on a.id = ep.almacen_id
        join corregido.ciudades c on c.id = a.ciudad_id
        left join inventario_expuesto ie
            on ie.almacen_id = ep.almacen_id and ie.clase = ep.clase
);
go

-- ================================================================
-- La consulta que utiliza el recurso creado
-- ================================================================

/*
Los diez episodios más severos de toda la red para los medicamentos
congelados, que son los más frágiles de las tres clases.
*/

select top 10
    almacen,
    ciudad,
    clase_conservacion,
    episodio,
    fecha_inicio,
    fecha_fin,
    lecturas,
    duracion_horas,
    ventana_exposicion_horas,
    desviacion_maxima_c,
    unidades_en_riesgo,
    horas_acumuladas,
    severidad_en_almacen
from corregido.f_episodios_riesgo_termico('Congelado')
order by duracion_horas desc, desviacion_maxima_c desc;
go

-- Vista completa de todos los episodios de todas las clases
select *
from corregido.f_episodios_riesgo_termico(default)
order by almacen, clase_conservacion, episodio;
go
