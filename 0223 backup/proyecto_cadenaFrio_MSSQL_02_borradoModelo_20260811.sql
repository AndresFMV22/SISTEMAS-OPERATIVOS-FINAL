-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: Microsoft SQL Server 2025

-- Este script lo uso cuando necesito reiniciar el modelo desde cero durante
-- las pruebas, antes de volver a correr el 01.

use cadena_frio_db;
go

-- Borrado de rutinas - Funciones y procedimientos
drop function if exists corregido.f_episodios_riesgo_termico;
drop function if exists corregido.f_disponible_por_lote;

drop procedure if exists corregido.p_eliminar_existencia;
drop procedure if exists corregido.p_registrar_lectura;
drop procedure if exists corregido.p_registrar_existencia;
go

-- Borrado de vistas
drop view if exists corregido.v_info_almacenes;
drop view if exists corregido.v_info_lotes;
drop view if exists corregido.v_info_medicamentos;
go

-- Las tablas del modelo corregido las elimino en orden inverso al de las
-- dependencias, si no, me tira error de llave foránea.
drop table if exists corregido.lecturas_temperatura;
drop table if exists corregido.existencias;
drop table if exists corregido.lotes;
drop table if exists corregido.medicamentos;
drop table if exists corregido.almacenes;
drop table if exists corregido.tipos_almacen;
drop table if exists corregido.ciudades;
drop table if exists corregido.formas_farmaceuticas;
drop table if exists corregido.fabricantes;
go

-- Borrado de la tabla de staging
drop table if exists inicial.cadena_frio;
go

-- De aquí para abajo es la zona de peligro: esto ya no es reiniciar el
-- modelo, es desmontarlo por completo, incluyendo el login y la base de
-- datos. Solo lo corro cuando de verdad quiero empezar desde cero.

drop schema if exists corregido;
drop schema if exists inicial;
go

-- Las sentencias siguientes las tengo que correr con el usuario
-- administrador (sa), porque el usuario de mínimos privilegios no puede
-- eliminar bases de datos ni inicios de sesión.

use master;
go

drop database if exists cadena_frio_db;
go

drop login if exists cadena_frio_login;
go
