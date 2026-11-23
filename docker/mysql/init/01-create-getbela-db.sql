-- GetBela: prepara la base de datos y el usuario de la aplicacion.
--
-- Este script corre UNA vez, cuando el datadir de MySQL esta vacio.
--
-- -----------------------------------------------------------------------------
-- SOBRE LAS VARIABLES DE ENTORNO
--
-- Los scripts de /docker-entrypoint-initdb.d NO reciben las variables de
-- entorno del contenedor como variables de shell: el entrypoint los
-- exporta, pero el servidor MySQL los procesa con su propio substitutor de
-- variables, que solo reconoce las de la forma @nombre_de_variable.
--
-- Por eso la password se referencia como @GETBELA_DB_PASSWORD y no como
-- ${GETBELA_DB_PASSWORD}: el binario de MySQL la resuelve desde el entorno
-- del proceso.
--
-- -----------------------------------------------------------------------------
-- POR QUE ESTE SCRIPT EXISTE
--
-- La imagen oficial de MySQL ya crea la base y el usuario a partir de
-- MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD (que define el .env del
-- grupo). Este script deja el GRANT explicito, para que los permisos
-- esten garantizados aunque el usuario ya existiera.
--
-- IMPORTANTE: la password sale del .env, nunca de un valor fijo. Una
-- version anterior de este archivo la sobreescribia con una constante de
-- desarrollo, lo que dejaba la base con una password distinta de la que
-- el backend usaba.
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS `getbela`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'getbela'@'%'
  IDENTIFIED BY '@GETBELA_DB_PASSWORD';

ALTER USER 'getbela'@'%'
  IDENTIFIED BY '@GETBELA_DB_PASSWORD';

GRANT ALL PRIVILEGES ON `getbela`.* TO 'getbela'@'%';

FLUSH PRIVILEGES;
