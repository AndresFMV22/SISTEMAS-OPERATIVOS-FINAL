-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

-- *************************************************
-- Borrado de las tablas para reinicio del modelo
-- *************************************************

-- Borrado de rutinas - Funciones y procedimientos
drop function corregido.f_analiza_excursiones_termicas;
drop function corregido.f_disponible_por_lote;
drop function corregido.f_registrar_lectura;

drop procedure corregido.p_eliminar_existencia;
drop procedure corregido.p_registrar_existencia;

-- Borrado de vistas
drop view corregido.v_info_almacenes;
drop view corregido.v_info_lotes;
drop view corregido.v_info_medicamentos;

-- Borrado de tablas del modelo corregido
-- Se eliminan en orden inverso al de las dependencias
drop table corregido.lecturas_temperatura;
drop table corregido.existencias;
drop table corregido.lotes;
drop table corregido.medicamentos;
drop table corregido.almacenes;
drop table corregido.tipos_almacen;
drop table corregido.ciudades;
drop table corregido.formas_farmaceuticas;
drop table corregido.fabricantes;

-- Borrado de la tabla de staging
drop table inicial.cadena_frio;

-- ===========================================================
-- Zona de peligro - Desmonte completo del modelo de datos
-- ===========================================================

-- Borrado del esquema corregido
drop schema corregido cascade;

-- Borrado del esquema inicial
drop schema inicial cascade;

-- Revocación de privilegios al usuario cadena_frio_usr y posterior eliminación
revoke all privileges on database cadena_frio_db from cadena_frio_usr;

drop user cadena_frio_usr;

-- Borrado de la base de datos cadena_frio_db
drop database cadena_frio_db;
