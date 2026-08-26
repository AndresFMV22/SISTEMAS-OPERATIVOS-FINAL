-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--
-- Autor: Jose Miguel Jaramillo, este archivo es mi parte en
-- SQL Server; la parte de Andrés en PostgreSQL está en
-- proyecto_cadenaFrio_PGSQL_01_scriptModelo_20260811.sql

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025




----En powershell
--- Descargar la imagen de SQL Server 2025.
docker pull mcr.microsoft.com/mssql/server:2025-latest

--- Crear el contenedor y correrlo, hay que usar ACCEPT_EULA=Y: para aceptar la licencia de Mssqlserv
docker run --name sqlsrv-cadenafrio -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=unaClav3" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2025-latest

-- Copio el archivo de datos al contenedor, lo necesito para el BULK INSERT
--- Crear dentro del contenedor el directorio donde se almacenará el archivo CSV, -p para evitar conflictos 
docker exec sqlsrv-cadenafrio mkdir -p /tmp/bulkload/cadena_frio

---Copiar el CSV al contenedor para poder utilizarlo posteriormente con BULK INSERT.
    ---Aca la dirección tiene que ser de donde se quiera sacar el .csv en mi caso la dirección que yo use fue: "C:\Users\Usuario\Downloads\datos_cadena_frio\datos_cadena_frio.csv" 
docker cp datos_cadena_frio/datos_cadena_frio.csv sqlsrv-cadenafrio:/tmp/bulkload/cadena_frio/datos_cadena_frio.csv

--- Ajustar los permisos del archivo como administrador del contenedor.
docker exec -u 0 sqlsrv-cadenafrio chmod 644 /tmp/bulkload/cadena_frio/datos_cadena_frio.csv

--- Verificar que el archivo fue copiado y tiene permisos de lectura.
docker exec sqlsrv-cadenafrio ls -lh /tmp/bulkload/cadena_frio/

--- Configurar la ruta permitida para operaciones de carga masiva de SQL Server.
docker exec -u 0 sqlsrv-cadenafrio /opt/mssql/bin/mssql-conf set bulkadmin.allowedpathslist "/tmp/bulkload/cadena_frio"

--- Verificar directamente la configuración guardada en mssql.conf.
docker exec -u 0 sqlsrv-cadenafrio cat /var/opt/mssql/mssql.conf

--- Instalar ACL porque el contenedor no disponía inicialmente de setfacl.
docker exec -u 0 sqlsrv-cadenafrio bash -c "apt-get update && apt-get install -y acl"

--- Dar al usuario mssql permiso explícito de lectura sobre el CSV.
docker exec -u 0 sqlsrv-cadenafrio setfacl -m u:mssql:r /tmp/bulkload/cadena_frio/datos_cadena_frio.csv   

--- Verificar que mssql tiene permiso de lectura mediante ACL.
docker exec -u 0 sqlsrv-cadenafrio getfacl /tmp/bulkload/cadena_frio/datos_cadena_frio.csv

--- Comprobar que el usuario mssql puede leer efectivamente el archivo.
docker exec -u 10001 sqlsrv-cadenafrio bash -c "head -n 2 /tmp/bulkload/cadena_frio/datos_cadena_frio.csv"
    

----En Docker Desktop, la pestaña Exec del contenedor

--- Primero hay que entrar a SQL Server como administrador mediante sqlcmd, como en NAC y acueducto solo que esto reemplaza el comando con psql
$ /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "unaClav3" -C
    ---En este entorno no se admiten bloques de código por eso usé comandos estructurados en líneas, hay que pegar primero el comando en la línea 1>, enter y al estar en 2> poner GO y de nuevo enter para poder ejecutar
-- Verificar el usuario de la sesión y la base de datos actual.
SELECT SUSER_NAME() AS usuario, DB_NAME() AS base_actual;
GO

-- Trabajar inicialmente en master para crear la base de datos.
USE master;
GO

-- Crear la base de datos del proyecto.
CREATE DATABASE cadena_frio_db;
GO

-- Verificar que la base de datos fue creada y se encuentra disponible.
SELECT name, state_desc
FROM sys.databases
WHERE name = 'cadena_frio_db';
GO

-- Cambiar a la base de datos del proyecto.
USE cadena_frio_db;
GO

--- Crear el login a nivel de servidor y establecer cadena_frio_db como DB predeterminada, este usuario es el que se autentica contra el servidor
CREATE LOGIN cadena_frio_login WITH PASSWORD = 'unaClav3',
    CHECK_POLICY = ON,
    DEFAULT_DATABASE = cadena_frio_db;
GO

--- Crear el usuario de la DB asociado al login de servidor, básicamente esta es la identidad que el login toma dentro de esta base de datos específica
CREATE USER cadena_frio_usr FOR LOGIN cadena_frio_login;
GO

-- privilegios para crear objetos dentro de esta base de datos únicamente
--- Permitir al usuario crear los esquemas y tablas necesarios para construir el modelo.
GRANT CREATE SCHEMA TO cadena_frio_usr;
GO
GRANT CREATE TABLE TO cadena_frio_usr;
GO

--- Permitir al usuario crear las vistas requeridas por el modelo.
GRANT CREATE VIEW TO cadena_frio_usr;
GO

--- Permitir al usuario crear los procedimientos almacenados requeridos.
GRANT CREATE PROCEDURE TO cadena_frio_usr;
GO

--- Permitir al usuario crear las funciones requeridas por el modelo.
GRANT CREATE FUNCTION TO cadena_frio_usr;
GO


-- privilegios de manipulación de datos sobre el esquema de trabajo
-- (se otorgan después de crear los esquemas, más abajo)

-- privilegio para consultar el catálogo del sistema y permitir consultar las definiciones de los objetos de la base de datos.
GRANT VIEW DEFINITION TO cadena_frio_usr;
GO

---- En master mediante Docker Exec

-- El permiso de carga masiva es de ámbito servidor y debe concederse desde master.
USE master;
GO

--- Permitir al login realizar operaciones de carga masiva para el CSV, esto es un permiso de ambito de servidor por esi no se le da al usr sino al login
GRANT ADMINISTER BULK OPERATIONS TO cadena_frio_login;
GO

    ---- En cadena_frio_db mediante Docker Exec

-- Volver a la base de datos del proyecto para realizar las verificaciones.
USE cadena_frio_db;
GO

-- Verificar que el login existe, es un SQL_LOGIN y tiene la BD correcta como predeterminada.
SELECT name, type_desc, default_database_name
FROM sys.server_principals
WHERE name = 'cadena_frio_login';
GO

-- Verificar que el usuario de base de datos existe y está asociado al proyecto.
SELECT name, type_desc
FROM sys.database_principals
WHERE name = 'cadena_frio_usr';
GO

-- Verificar los permisos concedidos al usuario de trabajo.
SELECT dp.permission_name, dp.state_desc
FROM sys.database_permissions dp
WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID('cadena_frio_usr');
GO


-- A partir de aquí dejo de usar el administrador. En mi IDE cierro la
-- conexión de sa y abro una nueva con el inicio de sesión cadena_frio_login,
-- que es con el que creo y opero todo el modelo de acá en adelante.
--
    
----En DBeaver: nueva conexión, host localhost, puerto 1433,
--             base de datos cadena_frio_db, usuario cadena_frio_login.

-- Evidencia 1: compruebo que no estoy usando el administrador ni sobre
-- la base de datos master.

SELECT SUSER_NAME() AS usuario_de_conexion,
       USER_NAME() AS usuario_de_base_de_datos,
       DB_NAME() AS base_de_datos_actual,
       @@SERVERNAME AS instancia;

-- Aqui la salida es cadena_frio_login (no sa) y cadena_frio_db (no master).

-- Evidencia 2: reviso que este usuario no pertenezca a ningún rol
-- administrativo.

SELECT IS_SRVROLEMEMBER('sysadmin') AS es_sysadmin,
       IS_SRVROLEMEMBER('securityadmin') AS es_securityadmin,
       IS_SRVROLEMEMBER('dbcreator') AS es_dbcreator,
       IS_ROLEMEMBER('db_owner') AS es_db_owner,
       IS_ROLEMEMBER('db_securityadmin') AS es_db_securityadmin;

-- Los cinco valores son en 0. Acá ya confirmo que el usuario
-- solo puede actuar dentro de cadena_frio_db y no tiene cómo escalar
-- privilegios.

-- Creación de las tablas.

-- Creamos esquema inicial
CREATE SCHEMA inicial;

-----CREACIÓN DE TABLAS CORREGIDAS

-- Primero se crean todas las tablas y sus restricciones; después se pueblan
-- desde inicial.cadena_frio. Se hace así para separar la definición del modelo
-- de la carga de datos y respetar el orden de las dependencias entre tablas.

---- Fabricantes
CREATE TABLE inicial.cadena_frio
(
    fabricante_nombre              nvarchar(200),
    medicamento_nombre             nvarchar(200),
    forma_farmaceutica             nvarchar(100),
    temperatura_min_c              nvarchar(50),
    temperatura_max_c              nvarchar(50),
    lote_codigo                    nvarchar(50),
    lote_fecha_fabricacion         nvarchar(50),
    lote_fecha_vencimiento         nvarchar(50),
    almacen_nombre                 nvarchar(200),
    almacen_ciudad                 nvarchar(100),
    almacen_tipo                   nvarchar(100),
    existencia_cantidad_disponible nvarchar(50),
    lectura_fecha_hora             nvarchar(50),
    lectura_temperatura_c          nvarchar(50)
);

-- Cargo el CSV. con bulk insert, tiene punto y coma como delimitador,
-- en UTF-8 y con encabezado. El CODEPAGE 65001 no funciona para SQL server 2025 sobre Linux
BULK INSERT inicial.cadena_frio
FROM '/tmp/bulkload/cadena_frio/datos_cadena_frio.csv'
WITH
(
    FIRSTROW = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);

-- Reviso que hayan quedado los 1.000 registros
SELECT COUNT(*) AS total_registros
FROM inicial.cadena_frio;


--Reviso que no se hayan corrompido Ñs ni tildes
SELECT TOP 20
    fabricante_nombre,
    forma_farmaceutica,
    almacen_ciudad,
    almacen_tipo
FROM inicial.cadena_frio
WHERE fabricante_nombre LIKE '%ñ%'
   OR fabricante_nombre LIKE '%á%'
   OR fabricante_nombre LIKE '%é%'
   OR fabricante_nombre LIKE '%í%'
   OR fabricante_nombre LIKE '%ó%'
   OR fabricante_nombre LIKE '%ú%'
   OR forma_farmaceutica LIKE '%ñ%'
   OR forma_farmaceutica LIKE '%á%'
   OR forma_farmaceutica LIKE '%é%'
   OR forma_farmaceutica LIKE '%í%'
   OR forma_farmaceutica LIKE '%ó%'
   OR forma_farmaceutica LIKE '%ú%'
   OR almacen_ciudad LIKE '%ñ%'
   OR almacen_ciudad LIKE '%á%'
   OR almacen_ciudad LIKE '%é%'
   OR almacen_ciudad LIKE '%í%'
   OR almacen_ciudad LIKE '%ó%'
   OR almacen_ciudad LIKE '%ú%';


--- De acá en adelante ya trabajo sobre el modelo normalizado.
---Creacion del esquema:
CREATE SCHEMA corregido;

---CREACIÓN DE TABLAS CORREGIDAS

-- Primero se crean todas las tablas y sus restricciones; después se pueblan
-- desde inicial.cadena_frio. Se hace así para separar la definición del modelo
-- de la carga de datos y respetar el orden de las dependencias entre tablas.

---- Fabricantes

CREATE TABLE corregido.fabricantes
(
    id          INT IDENTITY(1,1)
        CONSTRAINT fabricantes_pk PRIMARY KEY,

    descripcion NVARCHAR(150) NOT NULL
        CONSTRAINT fabricantes_descripcion_uk UNIQUE
);

--- Agregar metadatos descriptivos a la tabla y sus columnas.
EXEC sp_addextendedproperty
    'MS_Description',
    'Laboratorios que fabrican los medicamentos',
    'SCHEMA', 'corregido',
    'TABLE', 'fabricantes';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'Id del fabricante',
    'SCHEMA', 'corregido',
    'TABLE', 'fabricantes',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'Razón social del laboratorio fabricante',
    'SCHEMA', 'corregido',
    'TABLE', 'fabricantes',
    'COLUMN', 'descripcion';


---- Formas farmacéuticas

CREATE TABLE corregido.formas_farmaceuticas
(
    id          INT IDENTITY(1,1)
        CONSTRAINT formas_farmaceuticas_pk PRIMARY KEY,

    descripcion NVARCHAR(150) NOT NULL
        CONSTRAINT formas_farmaceuticas_descripcion_uk UNIQUE
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Presentaciones farmacéuticas de los medicamentos',
    'SCHEMA', 'corregido',
    'TABLE', 'formas_farmaceuticas';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la forma farmacéutica',
    'SCHEMA', 'corregido',
    'TABLE', 'formas_farmaceuticas',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'descripción de la forma farmacéutica',
    'SCHEMA', 'corregido',
    'TABLE', 'formas_farmaceuticas',
    'COLUMN', 'descripcion';


---- Ciudades

-- Ciudades, para saber dónde queda cada almacén.
CREATE TABLE corregido.ciudades
(
    id          INT IDENTITY(1,1)
        CONSTRAINT ciudades_pk PRIMARY KEY,

    descripcion NVARCHAR(150) NOT NULL
        CONSTRAINT ciudades_descripcion_uk UNIQUE
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Ciudades donde se ubican los almacenes',
    'SCHEMA', 'corregido',
    'TABLE', 'ciudades';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la ciudad',
    'SCHEMA', 'corregido',
    'TABLE', 'ciudades',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'nombre de la ciudad',
    'SCHEMA', 'corregido',
    'TABLE', 'ciudades',
    'COLUMN', 'descripcion';


---- Tipos de almacén

-- Y los tipos de almacén: solo son tres (Planta, Centro de distribución,
-- Unidad de salud), pero igual los saco a su propia tabla catálogo.
CREATE TABLE corregido.tipos_almacen
(
    id          INT IDENTITY(1,1)
        CONSTRAINT tipos_almacen_pk PRIMARY KEY,

    descripcion NVARCHAR(150) NOT NULL
        CONSTRAINT tipos_almacen_descripcion_uk UNIQUE
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Tipos de almacén de la red de distribución',
    'SCHEMA', 'corregido',
    'TABLE', 'tipos_almacen';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del tipo de almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'tipos_almacen',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'descripción del tipo de almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'tipos_almacen',
    'COLUMN', 'descripcion';


---- Medicamentos

-- Con medicamentos decidi  poner el rango de temperatura. cada medicamento siempre
-- trae el mismo par (mínima, máxima) en las 1.000 filas, así que es un
-- atributo del medicamento, no del lote ni de la lectura. Ponerlo acá me
-- evita esa redundancia.

CREATE TABLE corregido.medicamentos
(
    id                    INT IDENTITY(1,1)
        CONSTRAINT medicamentos_pk PRIMARY KEY,

    descripcion           NVARCHAR(200) NOT NULL
        CONSTRAINT medicamentos_descripcion_uk UNIQUE,

    fabricante_id         INT NOT NULL
        CONSTRAINT medicamentos_fabricante_fk
        REFERENCES corregido.fabricantes,

    forma_farmaceutica_id INT NOT NULL
        CONSTRAINT medicamentos_forma_farmaceutica_fk
        REFERENCES corregido.formas_farmaceuticas,

    temperatura_min_c     DECIMAL(5,2) NOT NULL,

    temperatura_max_c     DECIMAL(5,2) NOT NULL,

    CONSTRAINT medicamentos_rango_temperatura_ck
        CHECK (temperatura_min_c < temperatura_max_c)
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Medicamentos termosensibles distribuidos por la empresa',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del medicamento',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'nombre comercial del medicamento',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'descripcion';

--- Agregar metadatos descriptivos a la columna fabricante_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del laboratorio que fabrica el medicamento',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'fabricante_id';

--- Agregar metadatos descriptivos a la columna forma_farmaceutica_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la forma farmacéutica del medicamento',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'forma_farmaceutica_id';

--- Agregar metadatos descriptivos a la columna temperatura_min_c.
EXEC sp_addextendedproperty
    'MS_Description',
    'temperatura mínima de conservación en grados celsius',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'temperatura_min_c';

--- Agregar metadatos descriptivos a la columna temperatura_max_c.
EXEC sp_addextendedproperty
    'MS_Description',
    'temperatura máxima de conservación en grados celsius',
    'SCHEMA', 'corregido',
    'TABLE', 'medicamentos',
    'COLUMN', 'temperatura_max_c';


---- Lotes

-- Para lotes uso la misma verificación que hizo Andrés sobre el archivo:
-- ningún código de lote aparece asociado a dos medicamentos distintos, así
-- que un lote pertenece siempre a uno solo.

CREATE TABLE corregido.lotes
(
    id                INT IDENTITY(1,1)
        CONSTRAINT lotes_pk PRIMARY KEY,

    codigo            NVARCHAR(50) NOT NULL
        CONSTRAINT lotes_codigo_uk UNIQUE,

    medicamento_id    INT NOT NULL
        CONSTRAINT lotes_medicamento_fk
        REFERENCES corregido.medicamentos,

    fecha_fabricacion DATE NOT NULL,

    fecha_vencimiento DATE NOT NULL,

    CONSTRAINT lotes_vigencia_ck
        CHECK (fecha_vencimiento > fecha_fabricacion)
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Lotes de producción de cada medicamento',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del lote',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna codigo.
EXEC sp_addextendedproperty
    'MS_Description',
    'código del lote asignado por el fabricante',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes',
    'COLUMN', 'codigo';

--- Agregar metadatos descriptivos a la columna medicamento_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del medicamento al que pertenece el lote',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes',
    'COLUMN', 'medicamento_id';

--- Agregar metadatos descriptivos a la columna fecha_fabricacion.
EXEC sp_addextendedproperty
    'MS_Description',
    'fecha en la que se fabricó el lote',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes',
    'COLUMN', 'fecha_fabricacion';

--- Agregar metadatos descriptivos a la columna fecha_vencimiento.
EXEC sp_addextendedproperty
    'MS_Description',
    'fecha en la que vence el lote',
    'SCHEMA', 'corregido',
    'TABLE', 'lotes',
    'COLUMN', 'fecha_vencimiento';


---- Almacenes

-- Ahora los almacenes.
CREATE TABLE corregido.almacenes
(
    id              INT IDENTITY(1,1)
        CONSTRAINT almacenes_pk PRIMARY KEY,

    descripcion     NVARCHAR(200) NOT NULL
        CONSTRAINT almacenes_descripcion_uk UNIQUE,

    ciudad_id       INT NOT NULL
        CONSTRAINT almacenes_ciudad_fk
        REFERENCES corregido.ciudades,

    tipo_almacen_id INT NOT NULL
        CONSTRAINT almacenes_tipo_almacen_fk
        REFERENCES corregido.tipos_almacen
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Almacenes de la red de distribución',
    'SCHEMA', 'corregido',
    'TABLE', 'almacenes';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'almacenes',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna descripcion.
EXEC sp_addextendedproperty
    'MS_Description',
    'nombre del almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'almacenes',
    'COLUMN', 'descripcion';

--- Agregar metadatos descriptivos a la columna ciudad_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la ciudad donde se ubica el almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'almacenes',
    'COLUMN', 'ciudad_id';

--- Agregar metadatos descriptivos a la columna tipo_almacen_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del tipo de almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'almacenes',
    'COLUMN', 'tipo_almacen_id';


---- Existencias

-- Con existencias entro a la parte que más me costó pensar del modelo.
-- Un mismo lote se reparte entre varios almacenes y un mismo almacén guarda
-- decenas de lotes distintos, así que la relación es de muchos a muchos y
-- uso la pareja (lote, almacén) como su clave natural.

CREATE TABLE corregido.existencias
(
    id                  INT IDENTITY(1,1)
        CONSTRAINT existencias_pk PRIMARY KEY,

    lote_id             INT NOT NULL
        CONSTRAINT existencias_lote_fk
        REFERENCES corregido.lotes,

    almacen_id          INT NOT NULL
        CONSTRAINT existencias_almacen_fk
        REFERENCES corregido.almacenes,

    cantidad_disponible INT NOT NULL,

    CONSTRAINT existencias_lote_almacen_uk
        UNIQUE (lote_id, almacen_id),

    CONSTRAINT existencias_cantidad_ck
        CHECK (cantidad_disponible > 0)
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Cantidad disponible de cada lote en cada almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'existencias';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la existencia',
    'SCHEMA', 'corregido',
    'TABLE', 'existencias',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna lote_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del lote almacenado',
    'SCHEMA', 'corregido',
    'TABLE', 'existencias',
    'COLUMN', 'lote_id';

--- Agregar metadatos descriptivos a la columna almacen_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del almacén donde reposa el lote',
    'SCHEMA', 'corregido',
    'TABLE', 'existencias',
    'COLUMN', 'almacen_id';

--- Agregar metadatos descriptivos a la columna cantidad_disponible.
EXEC sp_addextendedproperty
    'MS_Description',
    'cantidad de unidades disponibles del lote en el almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'existencias',
    'COLUMN', 'cantidad_disponible';


---- Lecturas de temperatura

-- Y acá va la trampa del ejercicio: la existencia de un lote en un almacén
-- y la lectura de temperatura de ese almacén comparten fila en el CSV, pero
-- son hechos independientes. Las lecturas se toman de forma continua, sin
-- relación con qué lotes hay en la bodega en ese momento. Si las hubiera
-- dejado juntas en una sola tabla, habría metido una dependencia que no
-- existe en el dominio y me habría roto la tercera forma normal, así que
-- las separo en dos tablas, igual que en la versión de Andrés.

CREATE TABLE corregido.lecturas_temperatura
(
    id            INT IDENTITY(1,1)
        CONSTRAINT lecturas_temperatura_pk PRIMARY KEY,

    almacen_id    INT NOT NULL
        CONSTRAINT lecturas_temperatura_almacen_fk
        REFERENCES corregido.almacenes,

    fecha_hora    DATETIME2 NOT NULL,

    temperatura_c DECIMAL(5,2) NOT NULL,

    CONSTRAINT lecturas_temperatura_almacen_fecha_uk
        UNIQUE (almacen_id, fecha_hora)
);

--- Agregar metadatos descriptivos a la tabla.
EXEC sp_addextendedproperty
    'MS_Description',
    'Serie de lecturas del sensor de temperatura de cada almacén',
    'SCHEMA', 'corregido',
    'TABLE', 'lecturas_temperatura';

--- Agregar metadatos descriptivos a la columna id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id de la lectura',
    'SCHEMA', 'corregido',
    'TABLE', 'lecturas_temperatura',
    'COLUMN', 'id';

--- Agregar metadatos descriptivos a la columna almacen_id.
EXEC sp_addextendedproperty
    'MS_Description',
    'id del almacén donde se tomó la lectura',
    'SCHEMA', 'corregido',
    'TABLE', 'lecturas_temperatura',
    'COLUMN', 'almacen_id';

--- Agregar metadatos descriptivos a la columna fecha_hora.
EXEC sp_addextendedproperty
    'MS_Description',
    'fecha y hora en que se registró la lectura',
    'SCHEMA', 'corregido',
    'TABLE', 'lecturas_temperatura',
    'COLUMN', 'fecha_hora';

---Agregar metadatos descriptivos a la columna temperatura_c.
EXEC sp_addextendedproperty
    'MS_Description',
    'temperatura registrada en grados celsius',
    'SCHEMA', 'corregido',
    'TABLE', 'lecturas_temperatura',
    'COLUMN', 'temperatura_c';

----Verificacion de creacion de tablas
SELECT
    s.name AS esquema,
    t.name AS tabla
FROM sys.tables t
INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE s.name = 'corregido'
ORDER BY t.name;


---Verificacion de metadatos
SELECT
    s.name AS esquema,
    t.name AS tabla,
    c.name AS columna,
    ep.name AS propiedad,
    CAST(ep.value AS NVARCHAR(4000)) AS descripcion
FROM sys.extended_properties ep
LEFT JOIN sys.tables t
    ON ep.major_id = t.object_id
LEFT JOIN sys.schemas s
    ON t.schema_id = s.schema_id
LEFT JOIN sys.columns c
    ON ep.major_id = c.object_id
   AND ep.minor_id = c.column_id
WHERE s.name = 'corregido'
ORDER BY t.name, c.column_id, ep.name;




----POBLACIÓN DE LAS TABLAS CORREGIDAS

-- Primero se llenan las tablas catálogo y después las tablas que dependen de ellas, respetando el orden de las claves foráneas del modelo.


---- Fabricantes

-- La lleno desde el esquema inicial.
INSERT INTO corregido.fabricantes (descripcion)
(
    SELECT DISTINCT
        LTRIM(RTRIM(fabricante_nombre))
    FROM inicial.cadena_frio
);


---- Formas farmacéuticas

INSERT INTO corregido.formas_farmaceuticas (descripcion)
(
    SELECT DISTINCT
        LTRIM(RTRIM(forma_farmaceutica))
    FROM inicial.cadena_frio
);


---- Ciudades

INSERT INTO corregido.ciudades (descripcion)
(
    SELECT DISTINCT
        LTRIM(RTRIM(almacen_ciudad))
    FROM inicial.cadena_frio
);


---- Tipos de almacén

INSERT INTO corregido.tipos_almacen (descripcion)
(
    SELECT DISTINCT
        LTRIM(RTRIM(almacen_tipo))
    FROM inicial.cadena_frio
);


---- Medicamentos

INSERT INTO corregido.medicamentos
(
    descripcion,
    fabricante_id,
    forma_farmaceutica_id,
    temperatura_min_c,
    temperatura_max_c
)
(
    SELECT DISTINCT
        LTRIM(RTRIM(cf.medicamento_nombre)),
        f.id,
        ff.id,
        CAST(cf.temperatura_min_c AS DECIMAL(5,2)),
        CAST(cf.temperatura_max_c AS DECIMAL(5,2))
    FROM inicial.cadena_frio cf
        JOIN corregido.fabricantes f
            ON f.descripcion = LTRIM(RTRIM(cf.fabricante_nombre))
        JOIN corregido.formas_farmaceuticas ff
            ON ff.descripcion = LTRIM(RTRIM(cf.forma_farmaceutica))
);


---- Lotes

-- Para lotes uso la misma verificación que hizo Andrés sobre el archivo:
-- ningún código de lote aparece asociado a dos medicamentos distintos, así
-- que un lote pertenece siempre a uno solo.

INSERT INTO corregido.lotes
(
    codigo,
    medicamento_id,
    fecha_fabricacion,
    fecha_vencimiento
)
(
    SELECT DISTINCT
        LTRIM(RTRIM(cf.lote_codigo)),
        m.id,
        CAST(cf.lote_fecha_fabricacion AS DATE),
        CAST(cf.lote_fecha_vencimiento AS DATE)
    FROM inicial.cadena_frio cf
        JOIN corregido.medicamentos m
            ON m.descripcion = LTRIM(RTRIM(cf.medicamento_nombre))
);


---- Almacenes

INSERT INTO corregido.almacenes
(
    descripcion,
    ciudad_id,
    tipo_almacen_id
)
(
    SELECT DISTINCT
        LTRIM(RTRIM(cf.almacen_nombre)),
        c.id,
        ta.id
    FROM inicial.cadena_frio cf
        JOIN corregido.ciudades c
            ON c.descripcion = LTRIM(RTRIM(cf.almacen_ciudad))
        JOIN corregido.tipos_almacen ta
            ON ta.descripcion = LTRIM(RTRIM(cf.almacen_tipo))
);


---- Existencias

-- Un mismo lote puede aparecer en diferentes almacenes y un almacén puede
-- contener diferentes lotes; por eso se relacionan mediante sus respectivas
-- claves y se conserva la cantidad disponible de cada combinación.

INSERT INTO corregido.existencias
(
    lote_id,
    almacen_id,
    cantidad_disponible
)
(
    SELECT
        l.id,
        a.id,
        CAST(cf.existencia_cantidad_disponible AS INT)
    FROM inicial.cadena_frio cf
        JOIN corregido.lotes l
            ON l.codigo = LTRIM(RTRIM(cf.lote_codigo))
        JOIN corregido.almacenes a
            ON a.descripcion = LTRIM(RTRIM(cf.almacen_nombre))
);


---- Lecturas de temperatura

-- Las lecturas representan mediciones independientes realizadas en cada
-- almacén, por lo que se cargan separadamente de las existencias.

INSERT INTO corregido.lecturas_temperatura
(
    almacen_id,
    fecha_hora,
    temperatura_c
)
(
    SELECT
        a.id,
        CAST(cf.lectura_fecha_hora AS DATETIME2),
        CAST(cf.lectura_temperatura_c AS DECIMAL(5,2))
    FROM inicial.cadena_frio cf
        JOIN corregido.almacenes a
            ON a.descripcion = LTRIM(RTRIM(cf.almacen_nombre))
);

-- Con las nueve tablas cargadas, valido que todo haya entrado bien.
-- Los totales de referencia son los mismos que verificó Andrés en el
-- análisis previo del archivo.
SELECT 'fabricantes' AS tabla, COUNT(*) AS total
FROM corregido.fabricantes

UNION ALL

SELECT 'formas_farmaceuticas', COUNT(*)
FROM corregido.formas_farmaceuticas

UNION ALL

SELECT 'ciudades', COUNT(*)
FROM corregido.ciudades

UNION ALL

SELECT 'tipos_almacen', COUNT(*)
FROM corregido.tipos_almacen

UNION ALL

SELECT 'medicamentos', COUNT(*)
FROM corregido.medicamentos

UNION ALL

SELECT 'lotes', COUNT(*)
FROM corregido.lotes

UNION ALL

SELECT 'almacenes', COUNT(*)
FROM corregido.almacenes

UNION ALL

SELECT 'existencias', COUNT(*)
FROM corregido.existencias

UNION ALL

SELECT 'lecturas_temperatura', COUNT(*)
FROM corregido.lecturas_temperatura;
    
-- Aqupi la salida es: fabricantes 18, formas_farmaceuticas 6, ciudades 10,
--           tipos_almacen 3, medicamentos 67, lotes 259, almacenes 25,
--           existencias 1000, lecturas_temperatura 1000

    


----VISTAS DEL MODELO CORREGIDO

-- Ya con el modelo cargado, dejo tres vistas que uso seguido en las
-- consultas de la Etapa 4.

---- Información de medicamentos

CREATE VIEW corregido.v_info_medicamentos AS
SELECT
    m.id            AS medicamento_id,
    m.descripcion   AS medicamento,
    ff.descripcion  AS forma_farmaceutica,
    f.descripcion   AS fabricante,
    m.temperatura_min_c,
    m.temperatura_max_c
FROM corregido.medicamentos m
    JOIN corregido.formas_farmaceuticas ff
        ON ff.id = m.forma_farmaceutica_id
    JOIN corregido.fabricantes f
        ON f.id = m.fabricante_id;


---- Información de lotes

CREATE VIEW corregido.v_info_lotes AS
SELECT
    l.id          AS lote_id,
    l.codigo      AS lote_codigo,
    m.id          AS medicamento_id,
    m.descripcion AS medicamento,
    l.fecha_fabricacion,
    l.fecha_vencimiento
FROM corregido.lotes l
    JOIN corregido.medicamentos m
        ON m.id = l.medicamento_id;


---- Información de almacenes

CREATE VIEW corregido.v_info_almacenes AS
SELECT
    a.id           AS almacen_id,
    a.descripcion  AS almacen,
    c.descripcion  AS ciudad,
    ta.descripcion AS tipo_almacen
FROM corregido.almacenes a
    JOIN corregido.ciudades c
        ON c.id = a.ciudad_id
    JOIN corregido.tipos_almacen ta
        ON ta.id = a.tipo_almacen_id;


----RUTINAS DE APOYO PARA EL CRUD DEL MODELO

-- Por último, cuatro rutinas de apoyo para el CRUD del modelo. Las hice
-- para no escribir a mano el insert/update/delete cada vez, y para que
-- quien las use no necesite conocer los ids internos porque estas resuelven las
-- claves por nombre.

---- Create / Update de una existencia

CREATE OR ALTER PROCEDURE corregido.p_registrar_existencia
    @p_lote_codigo    NVARCHAR(50),
    @p_almacen_nombre NVARCHAR(200),
    @p_cantidad       INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_lote_id INT, @v_almacen_id INT;

    SELECT @v_lote_id = id
    FROM corregido.lotes
    WHERE codigo = @p_lote_codigo;

    SELECT @v_almacen_id = id
    FROM corregido.almacenes
    WHERE descripcion = @p_almacen_nombre;

    IF @v_lote_id IS NULL
        THROW 50001, 'No existe el lote con el código indicado', 1;

    IF @v_almacen_id IS NULL
        THROW 50002, 'No existe el almacén indicado', 1;

    IF EXISTS
    (
        SELECT 1
        FROM corregido.existencias
        WHERE lote_id = @v_lote_id
          AND almacen_id = @v_almacen_id
    )
        UPDATE corregido.existencias
        SET cantidad_disponible = @p_cantidad
        WHERE lote_id = @v_lote_id
          AND almacen_id = @v_almacen_id;
    ELSE
        INSERT INTO corregido.existencias
        (
            lote_id,
            almacen_id,
            cantidad_disponible
        )
        VALUES
        (
            @v_lote_id,
            @v_almacen_id,
            @p_cantidad
        );
END;


---- Create de una lectura de temperatura

CREATE OR ALTER PROCEDURE corregido.p_registrar_lectura
    @p_almacen_nombre NVARCHAR(200),
    @p_fecha_hora     DATETIME2,
    @p_temperatura    DECIMAL(5,2),
    @p_lectura_id     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_almacen_id INT;

    SELECT @v_almacen_id = id
    FROM corregido.almacenes
    WHERE descripcion = @p_almacen_nombre;

    IF @v_almacen_id IS NULL
        THROW 50002, 'No existe el almacén indicado', 1;

    INSERT INTO corregido.lecturas_temperatura
    (
        almacen_id,
        fecha_hora,
        temperatura_c
    )
    VALUES
    (
        @v_almacen_id,
        @p_fecha_hora,
        @p_temperatura
    );

    SET @p_lectura_id = SCOPE_IDENTITY();
END;


---- Delete de una existencia agotada

CREATE OR ALTER PROCEDURE corregido.p_eliminar_existencia
    @p_lote_codigo    NVARCHAR(50),
    @p_almacen_nombre NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE e
    FROM corregido.existencias e
        JOIN corregido.lotes l
            ON l.id = e.lote_id
        JOIN corregido.almacenes a
            ON a.id = e.almacen_id
    WHERE l.codigo = @p_lote_codigo
      AND a.descripcion = @p_almacen_nombre;

    IF @@ROWCOUNT = 0
        PRINT 'No había existencia de ese lote en ese almacén';
END;


---- Read del total disponible de un lote en toda la red

CREATE OR ALTER FUNCTION corregido.f_disponible_por_lote
(
    @p_lote_codigo NVARCHAR(50)
)
RETURNS INT
AS
BEGIN
    DECLARE @total INT;

    SELECT @total = ISNULL(SUM(e.cantidad_disponible), 0)
    FROM corregido.existencias e
        JOIN corregido.lotes l
            ON l.id = e.lote_id
    WHERE l.codigo = @p_lote_codigo;

    RETURN @total;
END;
-- Para cerrar, dejo la evidencia de que trabajé con privilegios mínimos:
-- no volví a tocar el usuario administrador después de crear la base de
-- datos, el login y el usuario.

-- Evidencia de quien quedó como propietario real de los objetos.

SELECT
    s.name AS esquema,
    t.name AS tabla,
    COALESCE(dp.name, sp.name) AS propietario
FROM sys.tables t
    JOIN sys.schemas s
        ON s.schema_id = t.schema_id
    LEFT JOIN sys.database_principals dp
        ON dp.principal_id = t.principal_id
    LEFT JOIN sys.database_principals sp
        ON sp.principal_id = s.principal_id
WHERE s.name IN ('inicial', 'corregido')
ORDER BY s.name, t.name;
-- |||||Aqui me sale cadena_frio_usr en las diez tablas, nunca dbo ni sa.


-- Evidencia lo que este usuario NO puede hacer. Corro las cuatro
-- sentencias siguientes una por una y capturo el mensaje de error de cada
-- una, aca es donde se demuestra que no tiene privilegios administrativos.

--   CREATE DATABASE permission denied in database 'master'
CREATE DATABASE base_intrusa;


CREATE LOGIN intruso WITH PASSWORD = 'unaClav3';

--   No se puede modificar el rol de servidor 'sysadmin'
ALTER SERVER ROLE sysadmin ADD MEMBER cadena_frio_login;


-- Evidencia para confirmar que no me quedé trabajando sobre la base de datos
-- del sistema.

SELECT
    DB_NAME() AS base_de_datos_de_trabajo,

    (
        SELECT COUNT(*)
        FROM sys.tables t
        JOIN sys.schemas s
            ON s.schema_id = t.schema_id
        WHERE s.name IN ('inicial', 'corregido')
    ) AS tablas_del_modelo,

    (
        SELECT COUNT(*)
        FROM sys.objects
        WHERE type IN ('P', 'FN', 'IF', 'TF')
          AND schema_id = SCHEMA_ID('corregido')
    ) AS rutinas_del_modelo;

