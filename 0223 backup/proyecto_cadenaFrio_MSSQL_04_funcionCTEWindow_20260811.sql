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

CREATE OR ALTER FUNCTION corregido.f_episodios_riesgo_termico
(
    @p_clase_conservacion NVARCHAR(50) = NULL
)
RETURNS TABLE
AS
RETURN
(
    WITH clases_conservacion AS
    (
        -- CTE 1: saco las clases de conservación del catálogo de
        -- medicamentos. Las derivo de los datos, no las escribo a mano.
        SELECT DISTINCT
            m.temperatura_min_c,
            m.temperatura_max_c,
            CASE
                WHEN m.temperatura_max_c <= 0 THEN 'Congelado'
                WHEN m.temperatura_max_c <= 8 THEN 'Refrigerado'
                ELSE 'Ambiente controlado'
            END AS clase
        FROM corregido.medicamentos m
    ),
    inventario_expuesto AS
    (
        -- CTE 2: cuento las unidades almacenadas de cada clase en cada
        -- almacén, que es el inventario que queda en riesgo cuando esa
        -- clase sale de rango.
        SELECT
            e.almacen_id,
            cc.clase,
            SUM(e.cantidad_disponible) AS unidades
        FROM corregido.existencias e
        JOIN corregido.lotes l
            ON l.id = e.lote_id
        JOIN corregido.medicamentos m
            ON m.id = l.medicamento_id
        JOIN clases_conservacion cc
            ON cc.temperatura_min_c = m.temperatura_min_c
           AND cc.temperatura_max_c = m.temperatura_max_c
        GROUP BY
            e.almacen_id,
            cc.clase
    ),
    lecturas_evaluadas AS
    (
        -- CTE 3: confronto cada lectura contra cada clase de conservación.
        -- Con lag y lead ubico la lectura dentro de la serie del almacén.
       SELECT
            lt.almacen_id,
            cc.clase,
            lt.fecha_hora,
            lt.temperatura_c,
            cc.temperatura_min_c,
            cc.temperatura_max_c,
            CASE
                WHEN lt.temperatura_c < cc.temperatura_min_c
                  OR lt.temperatura_c > cc.temperatura_max_c
                THEN 1
                ELSE 0
            END AS fuera_de_rango,
            LAG(lt.fecha_hora) OVER
            (
                PARTITION BY lt.almacen_id, cc.clase
                ORDER BY lt.fecha_hora
            ) AS lectura_anterior,
            LEAD(lt.fecha_hora) OVER
            (
                PARTITION BY lt.almacen_id, cc.clase
                ORDER BY lt.fecha_hora
            ) AS lectura_siguiente
        FROM corregido.lecturas_temperatura lt
        CROSS JOIN clases_conservacion cc
        WHERE @p_clase_conservacion IS NULL
           OR cc.clase = @p_clase_conservacion
    ),
    islas AS
    (
        -- CTE 4: acá aplico huecos e islas. La diferencia entre las dos
        -- numeraciones se mantiene constante mientras el estado de
        -- cumplimiento no cambie, así identifico cada racha de lecturas
        -- consecutivas.
        SELECT
            le.almacen_id,
            le.clase,
            le.fecha_hora,
            le.temperatura_c,
            le.temperatura_min_c,
            le.temperatura_max_c,
            le.fuera_de_rango,
            le.lectura_siguiente,
            ROW_NUMBER() OVER
            (
                PARTITION BY le.almacen_id, le.clase
                ORDER BY le.fecha_hora
            )
            -
            ROW_NUMBER() OVER
            (
                PARTITION BY le.almacen_id, le.clase, le.fuera_de_rango
                ORDER BY le.fecha_hora
            ) AS isla
        FROM lecturas_evaluadas le
    ),
    episodios AS
    (
        -- CTE 5: agrego cada isla que corresponda a una racha fuera de rango.
        SELECT
            i.almacen_id,
            i.clase,
            i.isla,
            MIN(i.fecha_hora) AS fecha_inicio,
            MAX(i.fecha_hora) AS fecha_fin,
            COUNT(*) AS lecturas,
            CAST(
                DATEDIFF(
                    SECOND,
                    MIN(i.fecha_hora),
                    MAX(i.fecha_hora)
                ) / 3600.0
                AS DECIMAL(12,2)
            ) AS duracion_horas,
            CAST(
                DATEDIFF(
                    SECOND,
                    MIN(i.fecha_hora),
                    COALESCE(
                        MAX(i.lectura_siguiente),
                        MAX(i.fecha_hora)
                    )
                ) / 3600.0
                AS DECIMAL(12,2)
            ) AS ventana_exposicion_horas,
            MAX(
                GREATEST(
                    i.temperatura_min_c - i.temperatura_c,
                    i.temperatura_c - i.temperatura_max_c
                )
            ) AS desviacion_maxima_c
        FROM islas i
        WHERE i.fuera_de_rango = 1
        GROUP BY
            i.almacen_id,
            i.clase,
            i.isla
    )


    -- Y en la consulta final numero los episodios, acumulo el tiempo de
    -- exposición y los ordeno por severidad dentro de cada almacén.
    SELECT
        a.descripcion AS almacen,
        c.descripcion AS ciudad,
        ep.clase AS clase_conservacion,
        ROW_NUMBER() OVER
        (
            PARTITION BY ep.almacen_id, ep.clase
            ORDER BY ep.fecha_inicio
        ) AS episodio,
        ep.fecha_inicio,
        ep.fecha_fin,
        ep.lecturas,
        ep.duracion_horas,
        ep.ventana_exposicion_horas,
        ep.desviacion_maxima_c,
        COALESCE(ie.unidades, 0) AS unidades_en_riesgo,
        CAST(
            SUM(ep.duracion_horas) OVER
            (
                PARTITION BY ep.almacen_id, ep.clase
                ORDER BY ep.fecha_inicio
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
            AS DECIMAL(12,2)
        ) AS horas_acumuladas,
        RANK() OVER
        (
            PARTITION BY ep.almacen_id
            ORDER BY
                ep.duracion_horas DESC,
                ep.desviacion_maxima_c DESC
        ) AS severidad_en_almacen
    FROM episodios ep
    JOIN corregido.almacenes a
        ON a.id = ep.almacen_id
    JOIN corregido.ciudades c
        ON c.id = a.ciudad_id
    LEFT JOIN inventario_expuesto ie
        ON ie.almacen_id = ep.almacen_id
       AND ie.clase = ep.clase
);


-- Ahora la consulta que la invoca. Elegí ver los diez episodios más severos
-- de toda la red para los medicamentos congelados, porque son los más
-- frágiles de las tres clases.

SELECT TOP 10
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
FROM corregido.f_episodios_riesgo_termico('Congelado')
ORDER BY
    duracion_horas DESC,
    desviacion_maxima_c DESC;

-- CONSULTA COMPLETA DE VERIFICACIÓN:
-- Y esta segunda consulta me da la vista completa, todos los episodios de
-- todas las clases.
SELECT *
FROM corregido.f_episodios_riesgo_termico(DEFAULT)
ORDER BY
    almacen,
    clase_conservacion,
    episodio;
