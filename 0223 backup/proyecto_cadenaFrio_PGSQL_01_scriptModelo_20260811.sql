-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--
-- Con José quedamos en implementar el mismo modelo, las mismas tablas y la
-- misma nomenclatura, cada uno en su propio motor. Este archivo es mi parte
-- en PostgreSQL; la de José en T-SQL queda en
-- proyecto_cadenaFrio_MSSQL_01_scriptModelo_20260811.sql

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

-- Para el motor use Docker. Así levanté la imagen y el contenedor:

-- Descargar la imagen
docker pull postgres:latest

-- Crear el contenedor
docker run --name psql-cadenafrio -e POSTGRES_PASSWORD=unaClav3 -d -p 5432:5432 postgres:latest

-- Ahora creo la base de datos y el usuario con el que voy a trabajar.
-- Todo este bloque lo corro conectado como el administrador (postgres),
-- porque crear una base de datos y crear un rol son las únicas dos cosas
-- que ese usuario me hace falta hacer con privilegios de administrador.

-- crear el esquema la base de datos
create database cadena_frio_db;

-- Conectarse a la base de datos
\c cadena_frio_db;

-- crear el usuario con el que se realizarán las acciones
create user cadena_frio_usr with encrypted password 'unaClav3';

-- Privilegios para establecer conexiones
grant connect on database cadena_frio_db to cadena_frio_usr;

-- privilegios para crear tablas temporales
grant temporary on database cadena_frio_db to cadena_frio_usr;

-- privilegios para crear objetos en la base de datos
grant create on database cadena_frio_db to cadena_frio_usr;

-- Privilegios de uso en el esquema
grant usage on schema public to cadena_frio_usr;

-- privilegios para crear objetos
grant create on schema public to cadena_frio_usr;

-- Privilegios sobre tablas existentes
grant select, insert, update, delete, trigger on all tables in schema public to cadena_frio_usr;

-- privilegios sobre secuencias existentes
grant usage, select on all sequences in schema public to cadena_frio_usr;

-- privilegios sobre funciones existentes
grant execute on all functions in schema public to cadena_frio_usr;

-- privilegios sobre procedimientos existentes
grant execute on all procedures in schema public to cadena_frio_usr;

-- privilegios sobre futuras tablas y secuencias
alter default privileges in schema public grant select, insert, update, delete, trigger on tables to cadena_frio_usr;

alter default privileges in schema public grant select, usage on sequences to cadena_frio_usr;

-- privilegios sobre futuras funciones y procedimientos
alter default privileges in schema public grant execute on routines to cadena_frio_usr;

-- Privilegios de consulta sobre el esquema information_schema
grant usage on schema information_schema to cadena_frio_usr;

-- A partir de aquí dejo de usar el usuario administrador. Todo el modelo
-- lo creo y lo opero con cadena_frio_usr, el usuario de mínimos privilegios
-- que acabo de crear.

\c cadena_frio_db cadena_frio_usr

-- ------------------------------------------------------------------
-- Evidencia 1: no se está trabajando con el usuario administrador
--              ni sobre la base de datos predeterminada
-- ------------------------------------------------------------------

select current_user            usuario_de_la_sesion,
       session_user            usuario_de_conexion,
       current_database()      base_de_datos_actual,
       inet_server_port()      puerto_tcp;

-- Con esto compruebo que la sesión quedó en cadena_frio_usr (no en postgres)
-- y en cadena_frio_db (no en la base predeterminada del motor).

-- ------------------------------------------------------------------
-- Evidencia 2: el rol no tiene atributos administrativos
-- ------------------------------------------------------------------

select rolname          rol,
       rolsuper         es_superusuario,
       rolcreatedb      puede_crear_bases,
       rolcreaterole    puede_crear_roles,
       rolbypassrls     omite_seguridad_de_filas,
       rolreplication   puede_replicar
from   pg_roles
where  rolname = current_user;

-- Todos los atributos me tienen que salir en false. Con eso confirmo que
-- el rol solo puede actuar dentro de su propia base de datos y no tiene
-- forma de escalar privilegios.

-- Ahora sí, la creación de las tablas.

-- Creamos esquema inicial
create schema inicial;

-- El archivo que me dieron es una sola tabla ancha y desnormalizada, así
-- que la recibo tal cual llega: todas las columnas como texto y sin
-- restricciones. Primero cargo el archivo completo acá y después reparto
-- los datos hacia el modelo normalizado.
create table inicial.cadena_frio
(
    fabricante_nombre               text,
    medicamento_nombre              text,
    forma_farmaceutica              text,
    temperatura_min_c               text,
    temperatura_max_c               text,
    lote_codigo                     text,
    lote_fecha_fabricacion          text,
    lote_fecha_vencimiento          text,
    almacen_nombre                  text,
    almacen_ciudad                  text,
    almacen_tipo                    text,
    existencia_cantidad_disponible  text,
    lectura_fecha_hora              text,
    lectura_temperatura_c           text
);

-- Antes de seguir, cargo el CSV. Viene con punto y coma como delimitador,
-- en UTF-8 y con encabezado. Desde psql, con \copy la ruta es relativa al
-- directorio donde estoy parado al invocar el cliente:
\copy inicial.cadena_frio from 'datos_cadena_frio/datos_cadena_frio.csv' with (format csv, header true, delimiter ';', encoding 'UTF8')

-- Esto también lo puedo hacer con el asistente de importación de DBeaver o
-- DataGrip, indicando el mismo delimitador y la misma codificación.

-- Reviso que hayan entrado los 1.000 registros
select count(*) total_registros from inicial.cadena_frio;

-- De acá en adelante ya trabajo sobre el modelo normalizado.
create schema corregido;

-- Empiezo por fabricantes.
create table corregido.fabricantes
(
    id          integer generated always as identity constraint fabricantes_pk primary key,
    descripcion text not null constraint fabricantes_descripcion_uk unique
);

comment on table corregido.fabricantes is 'Laboratorios que fabrican los medicamentos';
comment on column corregido.fabricantes.id is 'id del fabricante';
comment on column corregido.fabricantes.descripcion is 'razón social del laboratorio fabricante';

-- La lleno desde el esquema inicial
insert into corregido.fabricantes (descripcion)
(
    select distinct trim(fabricante_nombre)
    from inicial.cadena_frio
);

-- Sigo con formas farmacéuticas.
create table corregido.formas_farmaceuticas
(
    id          integer generated always as identity constraint formas_farmaceuticas_pk primary key,
    descripcion text not null constraint formas_farmaceuticas_descripcion_uk unique
);

comment on table corregido.formas_farmaceuticas is 'Presentaciones farmacéuticas de los medicamentos';
comment on column corregido.formas_farmaceuticas.id is 'id de la forma farmacéutica';
comment on column corregido.formas_farmaceuticas.descripcion is 'descripción de la forma farmacéutica';

insert into corregido.formas_farmaceuticas (descripcion)
(
    select distinct trim(forma_farmaceutica)
    from inicial.cadena_frio
);

-- Ciudades, para saber dónde queda cada almacén.
create table corregido.ciudades
(
    id          integer generated always as identity constraint ciudades_pk primary key,
    descripcion text not null constraint ciudades_descripcion_uk unique
);

comment on table corregido.ciudades is 'Ciudades donde se ubican los almacenes';
comment on column corregido.ciudades.id is 'id de la ciudad';
comment on column corregido.ciudades.descripcion is 'nombre de la ciudad';

insert into corregido.ciudades (descripcion)
(
    select distinct trim(almacen_ciudad)
    from inicial.cadena_frio
);

-- Y los tipos de almacén: son solo tres (Planta, Centro de distribución,
-- Unidad de salud), pero igual los saco a su propia tabla catálogo.
create table corregido.tipos_almacen
(
    id          integer generated always as identity constraint tipos_almacen_pk primary key,
    descripcion text not null constraint tipos_almacen_descripcion_uk unique
);

comment on table corregido.tipos_almacen is 'Tipos de almacén de la red de distribución';
comment on column corregido.tipos_almacen.id is 'id del tipo de almacén';
comment on column corregido.tipos_almacen.descripcion is 'descripción del tipo de almacén';

insert into corregido.tipos_almacen (descripcion)
(
    select distinct trim(almacen_tipo)
    from inicial.cadena_frio
);

-- Con medicamentos tuve que decidir dónde poner el rango de temperatura.
-- Revisé el archivo y cada medicamento siempre trae el mismo par (mínima,
-- máxima) en sus 1.000 filas, así que es un atributo del medicamento, no
-- del lote ni de la lectura. Ponerlo acá me evita esa redundancia.
create table corregido.medicamentos
(
    id                    integer generated always as identity constraint medicamentos_pk primary key,
    descripcion           text not null constraint medicamentos_descripcion_uk unique,
    fabricante_id         integer not null constraint medicamentos_fabricante_fk references corregido.fabricantes,
    forma_farmaceutica_id integer not null constraint medicamentos_forma_farmaceutica_fk references corregido.formas_farmaceuticas,
    temperatura_min_c     numeric(5, 2) not null,
    temperatura_max_c     numeric(5, 2) not null,
    constraint medicamentos_rango_temperatura_ck check (temperatura_min_c < temperatura_max_c)
);

comment on table corregido.medicamentos is 'Medicamentos termosensibles distribuidos por la empresa';
comment on column corregido.medicamentos.id is 'id del medicamento';
comment on column corregido.medicamentos.descripcion is 'nombre comercial del medicamento';
comment on column corregido.medicamentos.fabricante_id is 'id del laboratorio que fabrica el medicamento';
comment on column corregido.medicamentos.forma_farmaceutica_id is 'id de la forma farmacéutica del medicamento';
comment on column corregido.medicamentos.temperatura_min_c is 'temperatura mínima de conservación en grados celsius';
comment on column corregido.medicamentos.temperatura_max_c is 'temperatura máxima de conservación en grados celsius';

insert into corregido.medicamentos (descripcion, fabricante_id, forma_farmaceutica_id, temperatura_min_c, temperatura_max_c)
(
    select distinct
        trim(cf.medicamento_nombre),
        f.id,
        ff.id,
        cf.temperatura_min_c::numeric(5, 2),
        cf.temperatura_max_c::numeric(5, 2)
    from inicial.cadena_frio cf
        join corregido.fabricantes f on f.descripcion = trim(cf.fabricante_nombre)
        join corregido.formas_farmaceuticas ff on ff.descripcion = trim(cf.forma_farmaceutica)
);

-- Para lotes revisé algo puntual: si algún código de lote aparecía asociado
-- a dos medicamentos distintos. No encontré ningún caso, así que un lote
-- pertenece siempre a un solo medicamento y lo modelo así.
create table corregido.lotes
(
    id                integer generated always as identity constraint lotes_pk primary key,
    codigo            text not null constraint lotes_codigo_uk unique,
    medicamento_id    integer not null constraint lotes_medicamento_fk references corregido.medicamentos,
    fecha_fabricacion date not null,
    fecha_vencimiento date not null,
    constraint lotes_vigencia_ck check (fecha_vencimiento > fecha_fabricacion)
);

comment on table corregido.lotes is 'Lotes de producción de cada medicamento';
comment on column corregido.lotes.id is 'id del lote';
comment on column corregido.lotes.codigo is 'código del lote asignado por el fabricante';
comment on column corregido.lotes.medicamento_id is 'id del medicamento al que pertenece el lote';
comment on column corregido.lotes.fecha_fabricacion is 'fecha en la que se fabricó el lote';
comment on column corregido.lotes.fecha_vencimiento is 'fecha en la que vence el lote';

insert into corregido.lotes (codigo, medicamento_id, fecha_fabricacion, fecha_vencimiento)
(
    select distinct
        trim(cf.lote_codigo),
        m.id,
        cf.lote_fecha_fabricacion::date,
        cf.lote_fecha_vencimiento::date
    from inicial.cadena_frio cf
        join corregido.medicamentos m on m.descripcion = trim(cf.medicamento_nombre)
);

-- Ahora los almacenes.
create table corregido.almacenes
(
    id              integer generated always as identity constraint almacenes_pk primary key,
    descripcion     text not null constraint almacenes_descripcion_uk unique,
    ciudad_id       integer not null constraint almacenes_ciudad_fk references corregido.ciudades,
    tipo_almacen_id integer not null constraint almacenes_tipo_almacen_fk references corregido.tipos_almacen
);

comment on table corregido.almacenes is 'Almacenes de la red de distribución';
comment on column corregido.almacenes.id is 'id del almacén';
comment on column corregido.almacenes.descripcion is 'nombre del almacén';
comment on column corregido.almacenes.ciudad_id is 'id de la ciudad donde se ubica el almacén';
comment on column corregido.almacenes.tipo_almacen_id is 'id del tipo de almacén';

insert into corregido.almacenes (descripcion, ciudad_id, tipo_almacen_id)
(
    select distinct
        trim(cf.almacen_nombre),
        c.id,
        ta.id
    from inicial.cadena_frio cf
        join corregido.ciudades c on c.descripcion = trim(cf.almacen_ciudad)
        join corregido.tipos_almacen ta on ta.descripcion = trim(cf.almacen_tipo)
);

-- Con existencias entro a la parte que más me costó pensar del modelo.
-- Un mismo lote se reparte entre varios almacenes y un mismo almacén guarda
-- decenas de lotes distintos, así que la relación es de muchos a muchos y
-- uso la pareja (lote, almacén) como su clave natural.
create table corregido.existencias
(
    id                  integer generated always as identity constraint existencias_pk primary key,
    lote_id             integer not null constraint existencias_lote_fk references corregido.lotes,
    almacen_id          integer not null constraint existencias_almacen_fk references corregido.almacenes,
    cantidad_disponible integer not null,
    constraint existencias_lote_almacen_uk unique (lote_id, almacen_id),
    constraint existencias_cantidad_ck check (cantidad_disponible > 0)
);

comment on table corregido.existencias is 'Cantidad disponible de cada lote en cada almacén';
comment on column corregido.existencias.id is 'id de la existencia';
comment on column corregido.existencias.lote_id is 'id del lote almacenado';
comment on column corregido.existencias.almacen_id is 'id del almacén donde reposa el lote';
comment on column corregido.existencias.cantidad_disponible is 'cantidad de unidades disponibles del lote en el almacén';

insert into corregido.existencias (lote_id, almacen_id, cantidad_disponible)
(
    select
        l.id,
        a.id,
        cf.existencia_cantidad_disponible::integer
    from inicial.cadena_frio cf
        join corregido.lotes l on l.codigo = trim(cf.lote_codigo)
        join corregido.almacenes a on a.descripcion = trim(cf.almacen_nombre)
);

-- Y acá viene la trampa del ejercicio, la que casi se me pasa la primera
-- vez que miré el archivo: la existencia de un lote en un almacén y la
-- lectura de temperatura de ese almacén comparten fila en el CSV, pero son
-- hechos independientes. Las lecturas se toman de forma continua, sin
-- relación con qué lotes hay en la bodega en ese momento. Si las hubiera
-- dejado juntas en una sola tabla, habría metido una dependencia que no
-- existe en el dominio y me habría roto la tercera forma normal, así que
-- las separo en dos tablas.
create table corregido.lecturas_temperatura
(
    id            integer generated always as identity constraint lecturas_temperatura_pk primary key,
    almacen_id    integer not null constraint lecturas_temperatura_almacen_fk references corregido.almacenes,
    fecha_hora    timestamp not null,
    temperatura_c numeric(5, 2) not null,
    constraint lecturas_temperatura_almacen_fecha_uk unique (almacen_id, fecha_hora)
);

comment on table corregido.lecturas_temperatura is 'Serie de lecturas del sensor de temperatura de cada almacén';
comment on column corregido.lecturas_temperatura.id is 'id de la lectura';
comment on column corregido.lecturas_temperatura.almacen_id is 'id del almacén donde se tomó la lectura';
comment on column corregido.lecturas_temperatura.fecha_hora is 'fecha y hora en que se registró la lectura';
comment on column corregido.lecturas_temperatura.temperatura_c is 'temperatura registrada en grados celsius';

insert into corregido.lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
(
    select
        a.id,
        cf.lectura_fecha_hora::timestamp,
        cf.lectura_temperatura_c::numeric(5, 2)
    from inicial.cadena_frio cf
        join corregido.almacenes a on a.descripcion = trim(cf.almacen_nombre)
);

-- Con las nueve tablas cargadas, valido que todo haya entrado bien.
-- Los totales de referencia salen del análisis que hice antes del archivo.
select 'fabricantes' tabla, count(*) total from corregido.fabricantes
union all
select 'formas_farmaceuticas', count(*) from corregido.formas_farmaceuticas
union all
select 'ciudades', count(*) from corregido.ciudades
union all
select 'tipos_almacen', count(*) from corregido.tipos_almacen
union all
select 'medicamentos', count(*) from corregido.medicamentos
union all
select 'lotes', count(*) from corregido.lotes
union all
select 'almacenes', count(*) from corregido.almacenes
union all
select 'existencias', count(*) from corregido.existencias
union all
select 'lecturas_temperatura', count(*) from corregido.lecturas_temperatura;

-- Esperado: fabricantes 18, formas_farmaceuticas 6, ciudades 10,
--           tipos_almacen 3, medicamentos 67, lotes 259, almacenes 25,
--           existencias 1000, lecturas_temperatura 1000

-- Ya con el modelo cargado, dejo tres vistas que uso seguido en las
-- consultas de la Etapa 4.

create view corregido.v_info_medicamentos as
(
select
    m.id medicamento_id,
    m.descripcion medicamento,
    ff.descripcion forma_farmaceutica,
    f.descripcion fabricante,
    m.temperatura_min_c,
    m.temperatura_max_c
from corregido.medicamentos m
    join corregido.formas_farmaceuticas ff on ff.id = m.forma_farmaceutica_id
    join corregido.fabricantes f on f.id = m.fabricante_id
);

comment on view corregido.v_info_medicamentos is 'Medicamento con su fabricante, forma farmacéutica y rango de conservación';

create view corregido.v_info_lotes as
(
select
    l.id lote_id,
    l.codigo lote_codigo,
    m.id medicamento_id,
    m.descripcion medicamento,
    l.fecha_fabricacion,
    l.fecha_vencimiento
from corregido.lotes l
    join corregido.medicamentos m on m.id = l.medicamento_id
);

comment on view corregido.v_info_lotes is 'Lote con el medicamento al que pertenece y sus fechas de vigencia';

create view corregido.v_info_almacenes as
(
select
    a.id almacen_id,
    a.descripcion almacen,
    c.descripcion ciudad,
    ta.descripcion tipo_almacen
from corregido.almacenes a
    join corregido.ciudades c on c.id = a.ciudad_id
    join corregido.tipos_almacen ta on ta.id = a.tipo_almacen_id
);

comment on view corregido.v_info_almacenes is 'Almacén con su ciudad y tipo';

-- Por último, cuatro rutinas de apoyo para el CRUD del modelo. Las hice
-- para no tener que escribir a mano el insert/update/delete cada vez, y
-- para que quien las use no necesite conocer los ids internos: resuelven
-- las claves por nombre.

-- Create / Update de una existencia
create or replace procedure corregido.p_registrar_existencia(
    p_lote_codigo    text,
    p_almacen_nombre text,
    p_cantidad       integer
)
language plpgsql
as
$$
declare
    v_lote_id    integer;
    v_almacen_id integer;
begin
    select id into v_lote_id from corregido.lotes where codigo = p_lote_codigo;
    select id into v_almacen_id from corregido.almacenes where descripcion = p_almacen_nombre;

    if v_lote_id is null then
        raise exception 'No existe el lote con código %', p_lote_codigo;
    end if;

    if v_almacen_id is null then
        raise exception 'No existe el almacén %', p_almacen_nombre;
    end if;

    insert into corregido.existencias (lote_id, almacen_id, cantidad_disponible)
    values (v_lote_id, v_almacen_id, p_cantidad)
    on conflict (lote_id, almacen_id)
    do update set cantidad_disponible = excluded.cantidad_disponible;
end;
$$;

-- Create de una lectura de temperatura
create or replace function corregido.f_registrar_lectura(
    p_almacen_nombre text,
    p_fecha_hora     timestamp,
    p_temperatura    numeric
)
returns integer
language plpgsql
as
$$
declare
    v_almacen_id integer;
    v_lectura_id integer;
begin
    select id into v_almacen_id from corregido.almacenes where descripcion = p_almacen_nombre;

    if v_almacen_id is null then
        raise exception 'No existe el almacén %', p_almacen_nombre;
    end if;

    insert into corregido.lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
    values (v_almacen_id, p_fecha_hora, p_temperatura)
    returning id into v_lectura_id;

    return v_lectura_id;
end;
$$;

-- Delete de una existencia agotada
create or replace procedure corregido.p_eliminar_existencia(
    p_lote_codigo    text,
    p_almacen_nombre text
)
language plpgsql
as
$$
begin
    delete from corregido.existencias e
    using corregido.lotes l, corregido.almacenes a
    where e.lote_id = l.id
      and e.almacen_id = a.id
      and l.codigo = p_lote_codigo
      and a.descripcion = p_almacen_nombre;

    if not found then
        raise notice 'No había existencia del lote % en el almacén %', p_lote_codigo, p_almacen_nombre;
    end if;
end;
$$;

-- Read del total disponible de un lote en toda la red
create or replace function corregido.f_disponible_por_lote(p_lote_codigo text)
returns integer
language sql
stable
as
$$
    select coalesce(sum(e.cantidad_disponible), 0)::integer
    from corregido.existencias e
        join corregido.lotes l on l.id = e.lote_id
    where l.codigo = p_lote_codigo;
$$;

-- Para cerrar, dejo la evidencia de que en verdad trabajé con privilegios
-- mínimos: todo lo de arriba lo creó cadena_frio_usr, que es su propietario,
-- y no volví a tocar el usuario administrador después de crear la base de
-- datos y el rol.

-- Evidencia 3: reviso quién quedó como propietario real de los objetos.

select schemaname   esquema,
       tablename    tabla,
       tableowner   propietario
from   pg_tables
where  schemaname in ('inicial', 'corregido')
order by schemaname, tablename;

-- Me tiene que salir cadena_frio_usr en las diez tablas, nunca postgres.

-- Evidencia 4: lo que este usuario NO puede hacer. Corro las cuatro
-- sentencias siguientes una por una y capturo el mensaje de error de cada
-- una, eso es lo que demuestra que el rol no tiene privilegios administrativos.

-- create database base_intrusa;
--   ERROR: permission denied to create database

-- create user usuario_intruso with password 'x';
--   ERROR: permission denied to create role

-- alter user cadena_frio_usr with superuser;
--   ERROR: must be superuser to alter superuser roles

-- select * from pg_authid;
--   ERROR: permission denied for table pg_authid

-- Evidencia 5: confirmo que no me quedé trabajando sobre la base de datos
-- del sistema.

select current_database()                                  base_de_datos_de_trabajo,
       (select count(*) from pg_tables
        where schemaname in ('inicial','corregido'))        tablas_del_modelo,
       (select count(*) from information_schema.routines
        where routine_schema = 'corregido')                 rutinas_del_modelo;

-- Todo el modelo quedó en cadena_frio_db, dentro de los esquemas inicial y
-- corregido. No creé ningún objeto en la base de datos predeterminada del
-- motor ni en el esquema public.
