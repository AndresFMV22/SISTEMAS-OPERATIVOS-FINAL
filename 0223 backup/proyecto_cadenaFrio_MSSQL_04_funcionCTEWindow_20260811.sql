-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- Etapa 5: acá está la función con CTE y Window Functions, la misma
-- pregunta y el mismo diseño que Andrés implementó en PostgreSQL, pero
-- escrita en T-SQL.

/*
La pregunta en lenguaje natural

Cada almacén de la red guarda al mismo tiempo medicamentos de las tres
clases de conservación que maneja la empresa: congelados (-25 a -15 °C),
refrigerados (2 a 8 °C) y de ambiente controlado (15 a 25 °C). Un solo
sensor no puede estar simultáneamente en lo correcto para las tres, así que
toda lectura deja necesariamente una parte del inventario fuera de su rango.

La pregunta es entonces:

    Para cada almacén y cada clase de conservación, ¿cuáles fueron sus
    episodios de exposición térmica, entendidos como rachas de lecturas
    consecutivas fuera del rango? ¿Cuánto duró cada racha, qué tan lejos
    del límite llegó, cuántas unidades de esa clase había expuestas, cómo
    se acumula el tiempo de exposición a lo largo del periodo, y cuáles
    son los episodios más severos de cada almacén?

El plan previo que llevó a esta pregunta lo dejamos en el documento
plan_preguntas_etapa5.md que acompaña esta entrega.

Por qué me tocó usar Window Functions y no me alcanzaba con group by

Para identificar una racha de lecturas consecutivas fuera de rango hay que
comparar cada fila con su vecina en un orden determinado. Uso la técnica de
huecos e islas (gaps and islands): la diferencia entre dos numeraciones
row_number(), una sobre toda la serie del almacén y otra sobre las filas que
comparten el estado de cumplimiento, me da un identificador constante para
cada racha. No hay forma de sacar ese identificador con un group by, porque
el grupo al que pertenece una fila depende de la posición de las filas
anteriores, no de sus valores.

Las window functions que uso:
  - row_number()  dos veces, para armar las islas de lecturas consecutivas
  - lag()         para saber el instante de la lectura anterior
  - lead()        para acotar la ventana de exposición hasta la siguiente lectura
  - sum() over    para el tiempo de exposición acumulado dentro de cada almacén
  - rank()        para ordenar los episodios por severidad dentro de cada almacén

La sintaxis de estas funciones es igual en PostgreSQL y en SQL Server, por
eso la implementación me quedó equivalente a la de Andrés en los dos motores.
*/

-- El código de la función:

create or alter function corregido.f_episodios_riesgo_termico
(
    @p_clase_conservacion nvarchar(50) = null
)
returns table
as
return
(
    with clases_conservacion as (
        -- CTE 1: saco las clases de conservación del catálogo de
        -- medicamentos. Las derivo de los datos, no las escribo a mano.
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
        -- CTE 2: cuento las unidades almacenadas de cada clase en cada
        -- almacén, que es el inventario que queda en riesgo cuando esa
        -- clase sale de rango.
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
        -- CTE 3: confronto cada lectura contra cada clase de conservación.
        -- Con lag y lead ubico la lectura dentro de la serie del almacén.
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
        -- CTE 4: acá aplico huecos e islas. La diferencia entre las dos
        -- numeraciones se mantiene constante mientras el estado de
        -- cumplimiento no cambie, así identifico cada racha de lecturas
        -- consecutivas.
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
        -- CTE 5: agrego cada isla que corresponda a una racha fuera de rango.
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
    -- Y en la consulta final numero los episodios, acumulo el tiempo de
    -- exposición y los ordeno por severidad dentro de cada almacén.
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

-- Ahora la consulta que la invoca. Elegí ver los diez episodios más severos
-- de toda la red para los medicamentos congelados, porque son los más
-- frágiles de las tres clases.

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

-- Y esta segunda consulta me da la vista completa, todos los episodios de
-- todas las clases.
select *
from corregido.f_episodios_riesgo_termico(default)
order by almacen, clase_conservacion, episodio;
go
