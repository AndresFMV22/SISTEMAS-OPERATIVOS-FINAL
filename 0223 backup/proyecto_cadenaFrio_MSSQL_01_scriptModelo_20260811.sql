-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--
-- Ambos integrantes implementan el mismo modelo de datos, con las mismas
-- tablas y la misma nomenclatura. Este archivo es la implementación para
-- Microsoft SQL Server; la implementación equivalente en PL/pgSQL está en
-- proyecto_cadenaFrio_PGSQL_01_scriptModelo_20260811.sql

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- ***********************************
-- Abastecimiento de imagen en Docker
-- ***********************************

-- Descargar la imagen
docker pull mcr.microsoft.com/mssql/server:2025-latest

-- Crear el contenedor
docker run --name sqlsrv-cadenafrio -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=unaClav3" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2025-latest

-- Copiar el archivo de datos al contenedor, necesario para el BULK INSERT
docker exec sqlsrv-cadenafrio mkdir -p /var/opt/mssql/datos
docker cp datos_cadena_frio/datos_cadena_frio.csv sqlsrv-cadenafrio:/var/opt/mssql/datos/datos_cadena_frio.csv

-- ****************************************
-- Creación de base de datos y usuarios
-- ****************************************

-- Con usuario administrador (sa):

use master;
go

-- crear la base de datos
create database cadena_frio_db;
go

use cadena_frio_db;
go

-- crear el inicio de sesión a nivel de servidor
create login cadena_frio_login with password = 'unaClav3',
    check_policy = on,
    default_database = cadena_frio_db;
go

-- crear el usuario de base de datos asociado al inicio de sesión
create user cadena_frio_usr for login cadena_frio_login;
go

-- privilegios para crear objetos dentro de esta base de datos únicamente
grant create schema  to cadena_frio_usr;
grant create table   to cadena_frio_usr;
grant create view    to cadena_frio_usr;
grant create procedure to cadena_frio_usr;
grant create function to cadena_frio_usr;
go

-- privilegios de manipulación de datos sobre el esquema de trabajo
-- (se otorgan después de crear los esquemas, más abajo)

-- privilegio para consultar el catálogo del sistema de esta base de datos
grant view definition to cadena_frio_usr;
go

-- NOTA: no se agrega el usuario a db_owner ni a ningún rol administrativo.
-- Tampoco se le concede acceso a master ni a las demás bases del sistema.

-- *********************************************************************
-- Cambio de sesión: a partir de aquí NO se usa el usuario administrador
-- *********************************************************************

-- En un IDE, cerrar la conexión de sa y abrir una nueva con el inicio de
-- sesión cadena_frio_login. Todo el modelo se crea y se opera con ese
-- usuario de mínimos privilegios.
--
-- En DBeaver: nueva conexión, host localhost, puerto 1433,
--             base de datos cadena_frio_db, usuario cadena_frio_login.

-- ------------------------------------------------------------------
-- Evidencia 1: no se está trabajando con el usuario administrador
--              ni sobre la base de datos master
-- ------------------------------------------------------------------

select suser_name()  as usuario_de_conexion,
       user_name()   as usuario_de_base_de_datos,
       db_name()     as base_de_datos_actual,
       @@servername  as instancia;
go

-- Esperado: usuario cadena_frio_login (no sa)
--           base de datos cadena_frio_db (no master)

-- ------------------------------------------------------------------
-- Evidencia 2: el usuario no pertenece a ningún rol administrativo
-- ------------------------------------------------------------------

select is_srvrolemember('sysadmin')      as es_sysadmin,
       is_srvrolemember('securityadmin') as es_securityadmin,
       is_srvrolemember('dbcreator')     as es_dbcreator,
       is_rolemember('db_owner')         as es_db_owner,
       is_rolemember('db_securityadmin') as es_db_securityadmin;
go

-- Esperado: los cinco valores en 0. El usuario solo puede actuar dentro de
-- cadena_frio_db y no puede escalar privilegios.

-- ********************************
-- Creación de Tablas
-- ********************************

-- Creamos esquema inicial
create schema inicial;
go

-- El archivo de origen es una única tabla ancha y desnormalizada.
-- Se recibe tal cual llega, con todas las columnas como texto y sin
-- restricciones: primero ingresa el archivo completo y después se
-- reparte hacia el modelo normalizado.
create table inicial.cadena_frio
(
    fabricante_nombre               nvarchar(200),
    medicamento_nombre              nvarchar(200),
    forma_farmaceutica              nvarchar(100),
    temperatura_min_c               nvarchar(50),
    temperatura_max_c               nvarchar(50),
    lote_codigo                     nvarchar(50),
    lote_fecha_fabricacion          nvarchar(50),
    lote_fecha_vencimiento          nvarchar(50),
    almacen_nombre                  nvarchar(200),
    almacen_ciudad                  nvarchar(100),
    almacen_tipo                    nvarchar(100),
    existencia_cantidad_disponible  nvarchar(50),
    lectura_fecha_hora              nvarchar(50),
    lectura_temperatura_c           nvarchar(50)
);
go

-- ********************************************************
-- Cargar los datos del archivo CSV antes de continuar
-- ********************************************************

-- El archivo usa punto y coma como delimitador, viene en UTF-8 y trae
-- encabezado. CODEPAGE 65001 es UTF-8; sin él las tildes y la eñe se corrompen.
bulk insert inicial.cadena_frio
from '/var/opt/mssql/datos/datos_cadena_frio.csv'
with (
    firstrow        = 2,
    fieldterminator = ';',
    rowterminator   = '0x0a',
    codepage        = '65001',
    tablock
);
go

-- Alternativa: asistente de importación de DBeaver, indicando
-- delimitador ';' y codificación UTF-8.

-- Validamos que hayan ingresado los 1.000 registros
select count(*) as total_registros from inicial.cadena_frio;
go

-- *************************
-- Modelo de dato corregido
-- *************************
create schema corregido;
go

-- -----------------------
-- Tabla Fabricantes
-- -----------------------
create table corregido.fabricantes
(
    id          int identity(1,1) constraint fabricantes_pk primary key,
    descripcion nvarchar(150) not null constraint fabricantes_descripcion_uk unique
);
go

exec sp_addextendedproperty 'MS_Description', 'Laboratorios que fabrican los medicamentos',
     'SCHEMA', 'corregido', 'TABLE', 'fabricantes';
exec sp_addextendedproperty 'MS_Description', 'id del fabricante',
     'SCHEMA', 'corregido', 'TABLE', 'fabricantes', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'razón social del laboratorio fabricante',
     'SCHEMA', 'corregido', 'TABLE', 'fabricantes', 'COLUMN', 'descripcion';
go

-- Cargamos datos desde el esquema inicial
insert into corregido.fabricantes (descripcion)
(
    select distinct ltrim(rtrim(fabricante_nombre))
    from inicial.cadena_frio
);
go

-- -----------------------
-- Tabla Formas Farmaceuticas
-- -----------------------
create table corregido.formas_farmaceuticas
(
    id          int identity(1,1) constraint formas_farmaceuticas_pk primary key,
    descripcion nvarchar(150) not null constraint formas_farmaceuticas_descripcion_uk unique
);
go

exec sp_addextendedproperty 'MS_Description', 'Presentaciones farmacéuticas de los medicamentos',
     'SCHEMA', 'corregido', 'TABLE', 'formas_farmaceuticas';
exec sp_addextendedproperty 'MS_Description', 'id de la forma farmacéutica',
     'SCHEMA', 'corregido', 'TABLE', 'formas_farmaceuticas', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'descripción de la forma farmacéutica',
     'SCHEMA', 'corregido', 'TABLE', 'formas_farmaceuticas', 'COLUMN', 'descripcion';
go

insert into corregido.formas_farmaceuticas (descripcion)
(
    select distinct ltrim(rtrim(forma_farmaceutica))
    from inicial.cadena_frio
);
go

-- -----------------------
-- Tabla Ciudades
-- -----------------------
create table corregido.ciudades
(
    id          int identity(1,1) constraint ciudades_pk primary key,
    descripcion nvarchar(150) not null constraint ciudades_descripcion_uk unique
);
go

exec sp_addextendedproperty 'MS_Description', 'Ciudades donde se ubican los almacenes',
     'SCHEMA', 'corregido', 'TABLE', 'ciudades';
exec sp_addextendedproperty 'MS_Description', 'id de la ciudad',
     'SCHEMA', 'corregido', 'TABLE', 'ciudades', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'nombre de la ciudad',
     'SCHEMA', 'corregido', 'TABLE', 'ciudades', 'COLUMN', 'descripcion';
go

insert into corregido.ciudades (descripcion)
(
    select distinct ltrim(rtrim(almacen_ciudad))
    from inicial.cadena_frio
);
go

-- -----------------------
-- Tabla Tipos de Almacen
-- -----------------------
create table corregido.tipos_almacen
(
    id          int identity(1,1) constraint tipos_almacen_pk primary key,
    descripcion nvarchar(150) not null constraint tipos_almacen_descripcion_uk unique
);
go

exec sp_addextendedproperty 'MS_Description', 'Tipos de almacén de la red de distribución',
     'SCHEMA', 'corregido', 'TABLE', 'tipos_almacen';
exec sp_addextendedproperty 'MS_Description', 'id del tipo de almacén',
     'SCHEMA', 'corregido', 'TABLE', 'tipos_almacen', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'descripción del tipo de almacén',
     'SCHEMA', 'corregido', 'TABLE', 'tipos_almacen', 'COLUMN', 'descripcion';
go

insert into corregido.tipos_almacen (descripcion)
(
    select distinct ltrim(rtrim(almacen_tipo))
    from inicial.cadena_frio
);
go

-- -----------------------
-- Tabla Medicamentos
-- -----------------------

-- El rango de temperatura es un atributo del medicamento y no del lote ni de
-- la lectura: en los 1.000 registros del archivo, cada medicamento conserva
-- siempre el mismo par (mínima, máxima). Ubicarlo aquí elimina esa redundancia.
create table corregido.medicamentos
(
    id                    int identity(1,1) constraint medicamentos_pk primary key,
    descripcion           nvarchar(200) not null constraint medicamentos_descripcion_uk unique,
    fabricante_id         int not null constraint medicamentos_fabricante_fk references corregido.fabricantes,
    forma_farmaceutica_id int not null constraint medicamentos_forma_farmaceutica_fk references corregido.formas_farmaceuticas,
    temperatura_min_c     decimal(5,2) not null,
    temperatura_max_c     decimal(5,2) not null,
    constraint medicamentos_rango_temperatura_ck check (temperatura_min_c < temperatura_max_c)
);
go

exec sp_addextendedproperty 'MS_Description', 'Medicamentos termosensibles distribuidos por la empresa',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos';
exec sp_addextendedproperty 'MS_Description', 'id del medicamento',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'nombre comercial del medicamento',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'descripcion';
exec sp_addextendedproperty 'MS_Description', 'id del laboratorio que fabrica el medicamento',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'fabricante_id';
exec sp_addextendedproperty 'MS_Description', 'id de la forma farmacéutica del medicamento',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'forma_farmaceutica_id';
exec sp_addextendedproperty 'MS_Description', 'temperatura mínima de conservación en grados celsius',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'temperatura_min_c';
exec sp_addextendedproperty 'MS_Description', 'temperatura máxima de conservación en grados celsius',
     'SCHEMA', 'corregido', 'TABLE', 'medicamentos', 'COLUMN', 'temperatura_max_c';
go

insert into corregido.medicamentos (descripcion, fabricante_id, forma_farmaceutica_id, temperatura_min_c, temperatura_max_c)
(
    select distinct
        ltrim(rtrim(cf.medicamento_nombre)),
        f.id,
        ff.id,
        cast(cf.temperatura_min_c as decimal(5,2)),
        cast(cf.temperatura_max_c as decimal(5,2))
    from inicial.cadena_frio cf
        join corregido.fabricantes f on f.descripcion = ltrim(rtrim(cf.fabricante_nombre))
        join corregido.formas_farmaceuticas ff on ff.descripcion = ltrim(rtrim(cf.forma_farmaceutica))
);
go

-- -----------------------
-- Tabla Lotes
-- -----------------------

-- Un lote pertenece a un solo medicamento: se verificó sobre el archivo que
-- ningún código de lote aparece asociado a dos medicamentos distintos.
create table corregido.lotes
(
    id                int identity(1,1) constraint lotes_pk primary key,
    codigo            nvarchar(50) not null constraint lotes_codigo_uk unique,
    medicamento_id    int not null constraint lotes_medicamento_fk references corregido.medicamentos,
    fecha_fabricacion date not null,
    fecha_vencimiento date not null,
    constraint lotes_vigencia_ck check (fecha_vencimiento > fecha_fabricacion)
);
go

exec sp_addextendedproperty 'MS_Description', 'Lotes de producción de cada medicamento',
     'SCHEMA', 'corregido', 'TABLE', 'lotes';
exec sp_addextendedproperty 'MS_Description', 'id del lote',
     'SCHEMA', 'corregido', 'TABLE', 'lotes', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'código del lote asignado por el fabricante',
     'SCHEMA', 'corregido', 'TABLE', 'lotes', 'COLUMN', 'codigo';
exec sp_addextendedproperty 'MS_Description', 'id del medicamento al que pertenece el lote',
     'SCHEMA', 'corregido', 'TABLE', 'lotes', 'COLUMN', 'medicamento_id';
exec sp_addextendedproperty 'MS_Description', 'fecha en la que se fabricó el lote',
     'SCHEMA', 'corregido', 'TABLE', 'lotes', 'COLUMN', 'fecha_fabricacion';
exec sp_addextendedproperty 'MS_Description', 'fecha en la que vence el lote',
     'SCHEMA', 'corregido', 'TABLE', 'lotes', 'COLUMN', 'fecha_vencimiento';
go

insert into corregido.lotes (codigo, medicamento_id, fecha_fabricacion, fecha_vencimiento)
(
    select distinct
        ltrim(rtrim(cf.lote_codigo)),
        m.id,
        cast(cf.lote_fecha_fabricacion as date),
        cast(cf.lote_fecha_vencimiento as date)
    from inicial.cadena_frio cf
        join corregido.medicamentos m on m.descripcion = ltrim(rtrim(cf.medicamento_nombre))
);
go

-- -----------------------
-- Tabla Almacenes
-- -----------------------
create table corregido.almacenes
(
    id              int identity(1,1) constraint almacenes_pk primary key,
    descripcion     nvarchar(200) not null constraint almacenes_descripcion_uk unique,
    ciudad_id       int not null constraint almacenes_ciudad_fk references corregido.ciudades,
    tipo_almacen_id int not null constraint almacenes_tipo_almacen_fk references corregido.tipos_almacen
);
go

exec sp_addextendedproperty 'MS_Description', 'Almacenes de la red de distribución',
     'SCHEMA', 'corregido', 'TABLE', 'almacenes';
exec sp_addextendedproperty 'MS_Description', 'id del almacén',
     'SCHEMA', 'corregido', 'TABLE', 'almacenes', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'nombre del almacén',
     'SCHEMA', 'corregido', 'TABLE', 'almacenes', 'COLUMN', 'descripcion';
exec sp_addextendedproperty 'MS_Description', 'id de la ciudad donde se ubica el almacén',
     'SCHEMA', 'corregido', 'TABLE', 'almacenes', 'COLUMN', 'ciudad_id';
exec sp_addextendedproperty 'MS_Description', 'id del tipo de almacén',
     'SCHEMA', 'corregido', 'TABLE', 'almacenes', 'COLUMN', 'tipo_almacen_id';
go

insert into corregido.almacenes (descripcion, ciudad_id, tipo_almacen_id)
(
    select distinct
        ltrim(rtrim(cf.almacen_nombre)),
        c.id,
        ta.id
    from inicial.cadena_frio cf
        join corregido.ciudades c on c.descripcion = ltrim(rtrim(cf.almacen_ciudad))
        join corregido.tipos_almacen ta on ta.descripcion = ltrim(rtrim(cf.almacen_tipo))
);
go

-- -----------------------
-- Tabla Existencias
-- -----------------------

-- Un mismo lote puede repartirse entre varios almacenes y un mismo almacén
-- puede alojar decenas de lotes distintos: la relación es de muchos a muchos
-- y la pareja (lote, almacén) es su clave natural.
create table corregido.existencias
(
    id                  int identity(1,1) constraint existencias_pk primary key,
    lote_id             int not null constraint existencias_lote_fk references corregido.lotes,
    almacen_id          int not null constraint existencias_almacen_fk references corregido.almacenes,
    cantidad_disponible int not null,
    constraint existencias_lote_almacen_uk unique (lote_id, almacen_id),
    constraint existencias_cantidad_ck check (cantidad_disponible > 0)
);
go

exec sp_addextendedproperty 'MS_Description', 'Cantidad disponible de cada lote en cada almacén',
     'SCHEMA', 'corregido', 'TABLE', 'existencias';
exec sp_addextendedproperty 'MS_Description', 'id de la existencia',
     'SCHEMA', 'corregido', 'TABLE', 'existencias', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'id del lote almacenado',
     'SCHEMA', 'corregido', 'TABLE', 'existencias', 'COLUMN', 'lote_id';
exec sp_addextendedproperty 'MS_Description', 'id del almacén donde reposa el lote',
     'SCHEMA', 'corregido', 'TABLE', 'existencias', 'COLUMN', 'almacen_id';
exec sp_addextendedproperty 'MS_Description', 'cantidad de unidades disponibles del lote en el almacén',
     'SCHEMA', 'corregido', 'TABLE', 'existencias', 'COLUMN', 'cantidad_disponible';
go

insert into corregido.existencias (lote_id, almacen_id, cantidad_disponible)
(
    select
        l.id,
        a.id,
        cast(cf.existencia_cantidad_disponible as int)
    from inicial.cadena_frio cf
        join corregido.lotes l on l.codigo = ltrim(rtrim(cf.lote_codigo))
        join corregido.almacenes a on a.descripcion = ltrim(rtrim(cf.almacen_nombre))
);
go

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
    id            int identity(1,1) constraint lecturas_temperatura_pk primary key,
    almacen_id    int not null constraint lecturas_temperatura_almacen_fk references corregido.almacenes,
    fecha_hora    datetime2 not null,
    temperatura_c decimal(5,2) not null,
    constraint lecturas_temperatura_almacen_fecha_uk unique (almacen_id, fecha_hora)
);
go

exec sp_addextendedproperty 'MS_Description', 'Serie de lecturas del sensor de temperatura de cada almacén',
     'SCHEMA', 'corregido', 'TABLE', 'lecturas_temperatura';
exec sp_addextendedproperty 'MS_Description', 'id de la lectura',
     'SCHEMA', 'corregido', 'TABLE', 'lecturas_temperatura', 'COLUMN', 'id';
exec sp_addextendedproperty 'MS_Description', 'id del almacén donde se tomó la lectura',
     'SCHEMA', 'corregido', 'TABLE', 'lecturas_temperatura', 'COLUMN', 'almacen_id';
exec sp_addextendedproperty 'MS_Description', 'fecha y hora en que se registró la lectura',
     'SCHEMA', 'corregido', 'TABLE', 'lecturas_temperatura', 'COLUMN', 'fecha_hora';
exec sp_addextendedproperty 'MS_Description', 'temperatura registrada en grados celsius',
     'SCHEMA', 'corregido', 'TABLE', 'lecturas_temperatura', 'COLUMN', 'temperatura_c';
go

insert into corregido.lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
(
    select
        a.id,
        cast(cf.lectura_fecha_hora as datetime2),
        cast(cf.lectura_temperatura_c as decimal(5,2))
    from inicial.cadena_frio cf
        join corregido.almacenes a on a.descripcion = ltrim(rtrim(cf.almacen_nombre))
);
go

-- ********************************
-- Validación de la carga
-- ********************************

-- Los totales esperados provienen del análisis previo del archivo de origen.
select 'fabricantes' as tabla, count(*) as total from corregido.fabricantes
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
go

-- Esperado: fabricantes 18, formas_farmaceuticas 6, ciudades 10,
--           tipos_almacen 3, medicamentos 67, lotes 259, almacenes 25,
--           existencias 1000, lecturas_temperatura 1000

-- ********************************
-- Creación de Vistas
-- ********************************

create view corregido.v_info_medicamentos as
(
select
    m.id            as medicamento_id,
    m.descripcion   as medicamento,
    ff.descripcion  as forma_farmaceutica,
    f.descripcion   as fabricante,
    m.temperatura_min_c,
    m.temperatura_max_c
from corregido.medicamentos m
    join corregido.formas_farmaceuticas ff on ff.id = m.forma_farmaceutica_id
    join corregido.fabricantes f on f.id = m.fabricante_id
);
go

create view corregido.v_info_lotes as
(
select
    l.id          as lote_id,
    l.codigo      as lote_codigo,
    m.id          as medicamento_id,
    m.descripcion as medicamento,
    l.fecha_fabricacion,
    l.fecha_vencimiento
from corregido.lotes l
    join corregido.medicamentos m on m.id = l.medicamento_id
);
go

create view corregido.v_info_almacenes as
(
select
    a.id          as almacen_id,
    a.descripcion as almacen,
    c.descripcion as ciudad,
    ta.descripcion as tipo_almacen
from corregido.almacenes a
    join corregido.ciudades c on c.id = a.ciudad_id
    join corregido.tipos_almacen ta on ta.id = a.tipo_almacen_id
);
go

-- ***********************************************
-- Funciones y Procedimientos de apoyo al CRUD
-- ***********************************************

-- Create / Update de una existencia
create or alter procedure corregido.p_registrar_existencia
    @p_lote_codigo    nvarchar(50),
    @p_almacen_nombre nvarchar(200),
    @p_cantidad       int
as
begin
    set nocount on;

    declare @v_lote_id int, @v_almacen_id int;

    select @v_lote_id = id from corregido.lotes where codigo = @p_lote_codigo;
    select @v_almacen_id = id from corregido.almacenes where descripcion = @p_almacen_nombre;

    if @v_lote_id is null
        throw 50001, 'No existe el lote con el código indicado', 1;

    if @v_almacen_id is null
        throw 50002, 'No existe el almacén indicado', 1;

    if exists (select 1 from corregido.existencias
               where lote_id = @v_lote_id and almacen_id = @v_almacen_id)
        update corregido.existencias
        set cantidad_disponible = @p_cantidad
        where lote_id = @v_lote_id and almacen_id = @v_almacen_id;
    else
        insert into corregido.existencias (lote_id, almacen_id, cantidad_disponible)
        values (@v_lote_id, @v_almacen_id, @p_cantidad);
end;
go

-- Create de una lectura de temperatura
create or alter procedure corregido.p_registrar_lectura
    @p_almacen_nombre nvarchar(200),
    @p_fecha_hora     datetime2,
    @p_temperatura    decimal(5,2),
    @p_lectura_id     int output
as
begin
    set nocount on;

    declare @v_almacen_id int;
    select @v_almacen_id = id from corregido.almacenes where descripcion = @p_almacen_nombre;

    if @v_almacen_id is null
        throw 50002, 'No existe el almacén indicado', 1;

    insert into corregido.lecturas_temperatura (almacen_id, fecha_hora, temperatura_c)
    values (@v_almacen_id, @p_fecha_hora, @p_temperatura);

    set @p_lectura_id = scope_identity();
end;
go

-- Delete de una existencia agotada
create or alter procedure corregido.p_eliminar_existencia
    @p_lote_codigo    nvarchar(50),
    @p_almacen_nombre nvarchar(200)
as
begin
    set nocount on;

    delete e
    from corregido.existencias e
        join corregido.lotes l on l.id = e.lote_id
        join corregido.almacenes a on a.id = e.almacen_id
    where l.codigo = @p_lote_codigo
      and a.descripcion = @p_almacen_nombre;

    if @@rowcount = 0
        print 'No había existencia de ese lote en ese almacén';
end;
go

-- Read del total disponible de un lote en toda la red
create or alter function corregido.f_disponible_por_lote(@p_lote_codigo nvarchar(50))
returns int
as
begin
    declare @total int;

    select @total = isnull(sum(e.cantidad_disponible), 0)
    from corregido.existencias e
        join corregido.lotes l on l.id = e.lote_id
    where l.codigo = @p_lote_codigo;

    return @total;
end;
go

-- ***********************************************
-- Evidencia final de privilegios mínimos
-- ***********************************************

-- ------------------------------------------------------------------
-- Evidencia 3: quién es el propietario real de los objetos
-- ------------------------------------------------------------------

select s.name                    as esquema,
       t.name                    as tabla,
       coalesce(dp.name, sp.name) as propietario
from   sys.tables t
    join sys.schemas s on s.schema_id = t.schema_id
    left join sys.database_principals dp on dp.principal_id = t.principal_id
    left join sys.database_principals sp on sp.principal_id = s.principal_id
where  s.name in ('inicial', 'corregido')
order by s.name, t.name;
go

-- Esperado: propietario cadena_frio_usr en las diez tablas, nunca dbo ni sa.

-- ------------------------------------------------------------------
-- Evidencia 4: lo que el usuario NO puede hacer
-- ------------------------------------------------------------------

-- Las cuatro sentencias siguientes deben fallar. Ejecutarlas una por una y
-- capturar el mensaje de error es la demostración de que el usuario no tiene
-- privilegios administrativos.

-- use master;
--   El servidor principal "cadena_frio_login" no puede tener acceso a la base de datos "master"

-- create database base_intrusa;
--   CREATE DATABASE permission denied in database 'master'

-- create login intruso with password = 'unaClav3';
--   El servidor principal actual no puede crear inicios de sesión

-- alter server role sysadmin add member cadena_frio_login;
--   No se puede modificar el rol de servidor 'sysadmin'

-- ------------------------------------------------------------------
-- Evidencia 5: no se está trabajando sobre la base de datos del sistema
-- ------------------------------------------------------------------

select db_name()                                             as base_de_datos_de_trabajo,
       (select count(*) from sys.tables t join sys.schemas s
        on s.schema_id = t.schema_id
        where s.name in ('inicial','corregido'))              as tablas_del_modelo,
       (select count(*) from sys.objects
        where type in ('P','FN','IF','TF')
          and schema_id = schema_id('corregido'))             as rutinas_del_modelo;
go

-- Todo el modelo vive en cadena_frio_db, dentro de los esquemas inicial y
-- corregido. No se creó ningún objeto en master ni en el esquema dbo.
