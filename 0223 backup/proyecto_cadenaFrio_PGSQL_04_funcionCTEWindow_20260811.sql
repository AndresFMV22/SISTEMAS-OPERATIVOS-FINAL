-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

-- Etapa 5: acá está la función con CTE y Window Functions.

/*
La pregunta en lenguaje natural

Me di cuenta de algo mirando los datos: cada almacén de la red guarda al
mismo tiempo medicamentos de las tres clases de conservación que maneja la
empresa (congelados de -25 a -15 °C, refrigerados de 2 a 8 °C, y de ambiente
controlado de 15 a 25 °C). Un solo sensor no puede estar simultáneamente en
lo correcto para las tres, así que toda lectura deja necesariamente una
parte del inventario fuera de su rango.

De ahí saqué la pregunta:

    Para cada almacén y cada clase de conservación, ¿cuáles fueron sus
    episodios de exposición térmica, entendidos como rachas de lecturas
    consecutivas fuera del rango? ¿Cuánto duró cada racha, qué tan lejos
    del límite llegó, cuántas unidades de esa clase había expuestas, cómo
    se acumula el tiempo de exposición a lo largo del periodo, y cuáles
    son los episodios más severos de cada almacén?

Por qué llegué a esta pregunta y no a otra

El plan previo de exploración del dominio lo dejé en el documento
plan_preguntas_etapa5.md que acompaña esta entrega. De las diez preguntas
más recurrentes de una cadena de frío, encontré que las tres menos
exploradas eran la duración de las desviaciones, su agrupación en rachas y
la identificación del inventario concreto que estuvo en riesgo. Esta
pregunta las reúne a las tres.

La pregunta que cualquiera haría primero sobre este dominio es "¿cuántas
lecturas salieron de rango?", y esa se responde con un count y un group by
plano. El problema es que esa respuesta no distingue entre veinte picos
aislados y una racha sostenida de veinte lecturas seguidas. Operativamente
son dos fallas distintas, el primer caso suena a ruido del sensor y el
segundo a una falla real del equipo de refrigeración, y un conteo plano los
mete en el mismo número.

Por qué me tocó usar Window Functions y no me alcanzaba con group by

Para identificar una racha de lecturas consecutivas fuera de rango hay que
comparar cada fila con su vecina en un orden determinado. Usé la técnica de
huecos e islas (gaps and islands): la diferencia entre dos numeraciones
row_number(), una sobre toda la serie del almacén y otra sobre las filas que
comparten el estado de cumplimiento, me da un identificador constante para
cada racha. No hay forma de sacar ese identificador con un group by, porque
el grupo al que pertenece una fila depende de la posición de las filas
anteriores, no de sus valores.

Las window functions que terminé usando:
  - row_number()  dos veces, para armar las islas de lecturas consecutivas
  - lag()         para saber el instante de la lectura anterior
  - lead()        para acotar la ventana de exposición hasta la siguiente lectura
  - sum() over    para el tiempo de exposición acumulado dentro de cada almacén
  - rank()        para ordenar los episodios por severidad dentro de cada almacén
*/

-- El código de la función:

create or replace function corregido.f_episodios_riesgo_termico(
    p_clase_conservacion text default null
)
returns table
(
    almacen                   text,
    ciudad                    text,
    clase_conservacion        text,
    episodio                  bigint,
    fecha_inicio              timestamp,
    fecha_fin                 timestamp,
    lecturas                  bigint,
    duracion_horas            numeric,
    ventana_exposicion_horas  numeric,
    desviacion_maxima_c       numeric,
    unidades_en_riesgo        bigint,
    horas_acumuladas          numeric,
    severidad_en_almacen      bigint
)
language plpgsql
as
$$
begin
    return query
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
            end clase
        from corregido.medicamentos m
    ),
    inventario_expuesto as (
        -- CTE 2: cuento las unidades almacenadas de cada clase en cada
        -- almacén, que es el inventario que queda en riesgo cuando esa
        -- clase sale de rango.
        select
            e.almacen_id,
            cc.clase,
            sum(e.cantidad_disponible) unidades
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
            (lt.temperatura_c < cc.temperatura_min_c
             or lt.temperatura_c > cc.temperatura_max_c) fuera_de_rango,
            lag(lt.fecha_hora) over (
                partition by lt.almacen_id, cc.clase order by lt.fecha_hora
            ) lectura_anterior,
            lead(lt.fecha_hora) over (
                partition by lt.almacen_id, cc.clase order by lt.fecha_hora
            ) lectura_siguiente
        from corregido.lecturas_temperatura lt
            cross join clases_conservacion cc
        where p_clase_conservacion is null
           or cc.clase = p_clase_conservacion
    ),
    islas as (
        -- CTE 4: acá aplico huecos e islas. La diferencia entre las dos
        -- numeraciones se mantiene constante mientras el estado de
        -- cumplimiento no cambie, así identifico cada racha de lecturas
        -- consecutivas.
        select
            le.*,
            row_number() over (
                partition by le.almacen_id, le.clase order by le.fecha_hora
            )
            - row_number() over (
                partition by le.almacen_id, le.clase, le.fuera_de_rango
                order by le.fecha_hora
            ) isla
        from lecturas_evaluadas le
    ),
    episodios as (
        -- CTE 5: agrego cada isla que corresponda a una racha fuera de rango.
        select
            i.almacen_id,
            i.clase,
            i.isla,
            min(i.fecha_hora) fecha_inicio,
            max(i.fecha_hora) fecha_fin,
            count(*) lecturas,
            round(
                extract(epoch from (max(i.fecha_hora) - min(i.fecha_hora))) / 3600.0,
                2
            ) duracion_horas,
            round(
                extract(epoch from (
                    coalesce(max(i.lectura_siguiente), max(i.fecha_hora)) - min(i.fecha_hora)
                )) / 3600.0,
                2
            ) ventana_exposicion_horas,
            max(
                greatest(
                    i.temperatura_min_c - i.temperatura_c,
                    i.temperatura_c - i.temperatura_max_c
                )
            ) desviacion_maxima_c
        from islas i
        where i.fuera_de_rango
        group by i.almacen_id, i.clase, i.isla
    )
    -- Y en la consulta final numero los episodios, acumulo el tiempo de
    -- exposición y los ordeno por severidad dentro de cada almacén.
    select
        a.descripcion::text,
        c.descripcion::text,
        ep.clase::text,
        row_number() over (
            partition by ep.almacen_id, ep.clase order by ep.fecha_inicio
        ),
        ep.fecha_inicio,
        ep.fecha_fin,
        ep.lecturas,
        ep.duracion_horas,
        ep.ventana_exposicion_horas,
        ep.desviacion_maxima_c,
        coalesce(ie.unidades, 0)::bigint,
        round(
            sum(ep.duracion_horas) over (
                partition by ep.almacen_id, ep.clase
                order by ep.fecha_inicio
                rows between unbounded preceding and current row
            ),
            2
        ),
        rank() over (
            partition by ep.almacen_id order by ep.duracion_horas desc, ep.desviacion_maxima_c desc
        )
    from episodios ep
        join corregido.almacenes a on a.id = ep.almacen_id
        join corregido.ciudades c on c.id = a.ciudad_id
        left join inventario_expuesto ie
            on ie.almacen_id = ep.almacen_id and ie.clase = ep.clase
    order by a.descripcion, ep.clase, ep.fecha_inicio;
end;
$$;

comment on function corregido.f_episodios_riesgo_termico(text) is
    'Episodios de exposición térmica por almacén y clase de conservación, construidos con la técnica de huecos e islas sobre la serie de lecturas';

-- Ahora la consulta que la invoca. Elegí ver los diez episodios más severos
-- de toda la red para los medicamentos congelados, porque son los más
-- frágiles de las tres clases.

select
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
order by duracion_horas desc, desviacion_maxima_c desc
limit 10;

-- Y esta segunda consulta me da la vista completa, todos los episodios de
-- todas las clases.
select *
from corregido.f_episodios_riesgo_termico()
order by almacen, clase_conservacion, episodio;
