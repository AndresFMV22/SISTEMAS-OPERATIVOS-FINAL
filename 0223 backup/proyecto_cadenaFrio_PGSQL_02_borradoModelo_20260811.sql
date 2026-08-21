-- Examen No. 1 - Agosto 11 de 2026
-- Curso de Tópicos Avanzados de base de datos - UPB 202620
--
-- Integrantes del equipo:
--   Andrés Felipe Martínez - ID SIGAA 000549446 - PostgreSQL 18 (nube: MS Azure)
--   José Miguel Jaramillo  - ID SIGAA 000210186 - MS SQL Server 2025 (Docker local)
--

-- Proyecto: Cadena de frío de medicamentos - "Distri-Cold"
-- Motor de Base de datos: PostgreSQL 18.x

-- Este script lo uso cuando necesito reiniciar el modelo desde cero durante
-- las pruebas, antes de volver a correr el 01.

-- Borrado de rutinas - Funciones y procedimientos
drop function corregido.f_episodios_riesgo_termico;
drop function corregido.f_disponible_por_lote;
drop function corregido.f_registrar_lectura;

drop procedure corregido.p_eliminar_existencia;
drop procedure corregido.p_registrar_existencia;

-- Borrado de vistas
drop view corregido.v_info_almacenes;
drop view corregido.v_info_lotes;
drop view corregido.v_info_medicamentos;

-- Las tablas del modelo corregido las elimino en orden inverso al de las
-- dependencias, si no, me va a tirar error de llave foránea.
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

-- De aquí para abajo es la zona de peligro: esto ya no es reiniciar el
-- modelo, es desmontarlo por completo, incluyendo el usuario y la base
-- de datos. Solo lo corro cuando de verdad quiero empezar desde cero.

drop schema corregido cascade;

drop schema inicial cascade;

-- Antes de borrar el usuario le revoco los privilegios
revoke all privileges on database cadena_frio_db from cadena_frio_usr;

drop user cadena_frio_usr;

drop database cadena_frio_db;
