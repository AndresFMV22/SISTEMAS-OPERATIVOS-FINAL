-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--
-- Ambos integrantes implementan el mismo modelo de datos, con las mismas
-- tablas y la misma nomenclatura. Este archivo es la implementación para
-- PostgreSQL; la implementación equivalente en T-SQL está en el archivo
-- proyecto_cadenaFrio_MSSQL_01_scriptModelo_20260811.sql

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

-- ***********************************
-- Abastecimiento de imagen en Docker
-- ***********************************

-- Descargar la imagen
docker pull postgres:latest

-- Crear el contenedor
docker run --name psql-cadenafrio -e POSTGRES_PASSWORD=unaClav3 -d -p 5432:5432 postgres:latest

-- ****************************************
-- Creación de base de datos y usuarios
-- ****************************************

-- Con usuario Root:

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

-- *********************************************************************
-- Cambio de sesión: a partir de aquí NO se usa el usuario administrador
-- *********************************************************************

-- Todo el modelo se crea y se opera con el usuario de mínimos privilegios.
-- El usuario administrador (postgres) solo se empleó para las dos acciones
-- que ningún otro rol puede realizar: crear la base de datos y crear el rol.

\c cadena_frio_db cadena_frio_usr

-- ------------------------------------------------------------------
-- Evidencia 1: no se está trabajando con el usuario administrador
--              ni sobre la base de datos predeterminada
-- ------------------------------------------------------------------

select current_user            usuario_de_la_sesion,
       session_user            usuario_de_conexion,
       current_database()      base_de_datos_actual,
       inet_server_port()      puerto_tcp;

-- Esperado: usuario cadena_frio_usr (no postgres)
--           base de datos cadena_frio_db (no la predeterminada postgres)

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

-- Esperado: todos los atributos en false. El rol solo puede actuar dentro
-- de su propia base de datos y no puede escalar privilegios.

-- ********************************
-- Creación de Tablas
-- ********************************

-- Creamos esquema inicial
create schema inicial;

-- El archivo de origen es una única tabla ancha y desnormalizada.
-- Se recibe tal cual llega, con todas las columnas como texto y sin
-- restricciones: primero ingresa el archivo completo y después se
-- reparte hacia el modelo normalizado.
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

-- ********************************************************
-- Cargar los datos del archivo CSV antes de continuar
-- ********************************************************

-- El archivo usa punto y coma como delimitador, viene en UTF-8 y trae encabezado.
-- Desde psql, con \copy la ruta es relativa al directorio donde se invoca el cliente:
\copy inicial.cadena_frio from 'datos_cadena_frio/datos_cadena_frio.csv' with (format csv, header true, delimiter ';', encoding 'UTF8')

-- También puede realizarse con el asistente de importación de DBeaver o DataGrip,
-- indicando delimitador ';' y codificación UTF-8.

-- Validamos que hayan ingresado los 1.000 registros
select count(*) total_registros from inicial.cadena_frio;

-- *************************
-- Modelo de dato corregido
-- *************************
create schema corregido;

-- -----------------------
-- Tabla Fabricantes
-- -----------------------
create table corregido.fabricantes
(
    id          integer generated always as identity constraint fabricantes_pk primary key,
    descripcion text not null constraint fabricantes_descripcion_uk unique
);

comment on table corregido.fabricantes is 'Laboratorios que fabrican los medicamentos';
comment on column corregido.fabricantes.id is 'id del fabricante';
comment on column corregido.fabricantes.descripcion is 'razón social del laboratorio fabricante';

-- Cargamos datos desde el esquema inicial
insert into corregido.fabricantes (descripcion)
(
    select distinct trim(fabricante_nombre)
    from inicial.cadena_frio
);

-- -----------------------
-- Tabla Formas Farmaceuticas
-- -----------------------
create table corregido.formas_farmaceuticas
(
    id          integer generated always as identity constraint formas_farmaceuticas_pk primary key,
    descripcion text not null constraint formas_farmaceuticas_descripcion_uk unique
);

comment on table corregido.formas_farmaceuticas is 'Presentaciones farmacéuticas de los medicamentos';
comment on column corregido.formas_farmaceuticas.id is 'id de la forma farmacéutica';
comment on column corregido.formas_farmaceuticas.descripcion is 'descripción de la forma farmacéutica';

-- Cargamos datos desde el esquema inicial
insert into corregido.formas_farmaceuticas (descripcion)
(
    select distinct trim(forma_farmaceutica)
    from inicial.cadena_frio
);

-- -----------------------
-- Tabla Ciudades
-- -----------------------
create table corregido.ciudades
(
    id          integer generated always as identity constraint ciudades_pk primary key,
    descripcion text not null constraint ciudades_descripcion_uk unique
);

comment on table corregido.ciudades is 'Ciudades donde se ubican los almacenes';
comment on column corregido.ciudades.id is 'id de la ciudad';
comment on column corregido.ciudades.descripcion is 'nombre de la ciudad';

-- Cargamos datos desde el esquema inicial
insert into corregido.ciudades (descripcion)
(
    select distinct trim(almacen_ciudad)
    from inicial.cadena_frio
);

-- -----------------------
-- Tabla Tipos de Almacen
-- -----------------------
create table corregido.tipos_almacen
(
    id          integer generated always as identity constraint tipos_almacen_pk primary key,
    descripcion text not null constraint tipos_almacen_descripcion_uk unique
);

comment on table corregido.tipos_almacen is 'Tipos de almacén de la red de distribución';
comment on column corregido.tipos_almacen.id is 'id del tipo de almacén';
comment on column corregido.tipos_almacen.descripcion is 'descripción del tipo de almacén';

-- Cargamos datos desde el esquema inicial
insert into corregido.tipos_almacen (descripcion)
(
    select distinct trim(almacen_tipo)
    from inicial.cadena_frio
);

-- -----------------------
-- Tabla Medicamentos
-- -----------------------

-- El rango de temperatura es un atributo del medicamento y no del lote ni de
-- la lectura: en los 1.000 registros del archivo, cada medicamento conserva
-- siempre el mismo par (mínima, máxima). Ubicarlo aquí elimina esa redundancia.
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

-- Cargamos datos desde el esquema inicial
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

-- -----------------------
-- Tabla Lotes
-- -----------------------

-- Un lote pertenece a un solo medicamento: se verificó sobre el archivo que
-- ningún código de lote aparece asociado a dos medicamentos distintos.
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

-- Cargamos datos desde el esquema inicial
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

-- -----------------------
-- Tabla Almacenes
-- -----------------------
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

-- Cargamos datos desde el esquema inicial
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

-- -----------------------
-- Tabla Existencias
-- -----------------------

-- Un mismo lote puede repartirse entre varios almacenes y un mismo almacén
-- puede alojar decenas de lotes distintos: la relación es de muchos a muchos
-- y la pareja (lote, almacén) es su clave natural.
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

-- Cargamos datos desde el esquema inicial
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

-- ---------------------------
-- Tabla Lecturas de Temperatura
-- ---------------------------

-- Decisión de diseño central del modelo: la existencia de un lote en un almacén
-- y la lectura de temperatura de ese almacén comparten fila en el archivo de
-- origen, pero son hechos independientes. Las lecturas se registran de forma
-- continua, sin relación con qué lotes se encuentran en la bodega en ese
-- instante. Mantenerlas en una sola tabla introduciría una dependencia que no
-- existe en el dominio y rompería la tercera forma normal.
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

-- Cargamos datos desde el esquema inicial
insert into corregido.lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
(
    select
        a.id,
        cf.lectura_fecha_hora::timestamp,
        cf.lectura_temperatura_c::numeric(5, 2)
    from inicial.cadena_frio cf
        join corregido.almacenes a on a.descripcion = trim(cf.almacen_nombre)
);

-- ********************************
-- Validación de la carga
-- ********************************

-- Los totales esperados provienen del análisis previo del archivo de origen.
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

-- ********************************
-- Creación de Vistas
-- ********************************

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

-- ***********************************************
-- Funciones y Procedimientos de apoyo al CRUD
-- ***********************************************

-- Encapsulan las escrituras habituales sobre el modelo y resuelven por nombre
-- las claves subrogadas, de modo que quien consume el modelo no necesita
-- conocer los identificadores internos.

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

-- ***********************************************
-- Evidencia final de privilegios mínimos
-- ***********************************************

-- Los objetos anteriores fueron creados por cadena_frio_usr, que es su
-- propietario. No se requirió el usuario administrador en ningún momento
-- posterior a la creación de la base de datos y del rol.

-- ------------------------------------------------------------------
-- Evidencia 3: quién es el propietario real de los objetos
-- ------------------------------------------------------------------

select schemaname   esquema,
       tablename    tabla,
       tableowner   propietario
from   pg_tables
where  schemaname in ('inicial', 'corregido')
order by schemaname, tablename;

-- Esperado: propietario cadena_frio_usr en las diez tablas, nunca postgres.

-- ------------------------------------------------------------------
-- Evidencia 4: lo que el usuario NO puede hacer
-- ------------------------------------------------------------------

-- Las cuatro sentencias siguientes deben fallar. Ejecutarlas una por una y
-- capturar el mensaje de error es la demostración de que el rol no tiene
-- privilegios administrativos.

-- create database base_intrusa;
--   ERROR: permission denied to create database

-- create user usuario_intruso with password 'x';
--   ERROR: permission denied to create role

-- alter user cadena_frio_usr with superuser;
--   ERROR: must be superuser to alter superuser roles

-- select * from pg_authid;
--   ERROR: permission denied for table pg_authid

-- ------------------------------------------------------------------
-- Evidencia 5: no se está trabajando sobre la base de datos del sistema
-- ------------------------------------------------------------------

select current_database()                                  base_de_datos_de_trabajo,
       (select count(*) from pg_tables
        where schemaname in ('inicial','corregido'))        tablas_del_modelo,
       (select count(*) from information_schema.routines
        where routine_schema = 'corregido')                 rutinas_del_modelo;

-- Todo el modelo vive en cadena_frio_db, dentro de los esquemas inicial y
-- corregido. No se creó ningún objeto en la base de datos predeterminada
-- del motor ni en el esquema public.
