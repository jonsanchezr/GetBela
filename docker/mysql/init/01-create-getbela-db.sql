-- GetBela: prepara la base de datos y el usuario de la aplicacion.
--
-- Este script corre UNA vez, cuando el datadir de MySQL esta vacio.
--
-- -----------------------------------------------------------------------------
-- POR QUE ESTE SCRIPT NO CREA EL USUARIO
--
-- La imagen oficial de MySQL ya crea la base y el usuario con las variables
-- MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD, que el compose define desde
-- el .env del grupo. Ese mecanismo es el que funciona: el entrypoint los
-- consume directamente.
--
-- Una version anterior de este archivo hacia
--
--   CREATE USER IF NOT EXISTS 'getbela'@'%' IDENTIFIED BY '@GETBELA_DB_PASSWORD';
--   ALTER USER 'getbela'@'%' IDENTIFIED BY '@GETBELA_DB_PASSWORD';
--
-- con la intention de no dejar la password fija en el repositorio. El
-- problema es que el substitutor de variables de MySQL NO expande esa
-- variable dentro de un `IDENTIFIED BY` de un script de init: la sentencia
-- queda con el literal y deja al usuario con una password que no es la del
-- .env. El backend se conecta con la del .env y recibe
-- "Access denied for user 'getbela'@'172.20.0.4'".
--
-- Por eso el usuario NO se crea aqui: lo crea la imagen oficial, que si
-- aplica las variables correctamente. Este script se limita a garantizar los
-- permisos, que es idempotente y no toca la password.
--
-- -----------------------------------------------------------------------------
-- POR QUE EL GRANT ES NECESARIO
--
-- El GRANT explicito cubre el caso en que el usuario existiera de una
-- corrida anterior con permisos distintos: `GRANT ALL` sobre la base del
-- grupo es idempotente y no altera la password.
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS `getbela`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON `getbela`.* TO 'getbela'@'%';

FLUSH PRIVILEGES;
