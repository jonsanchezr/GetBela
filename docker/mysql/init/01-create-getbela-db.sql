-- GetBela: prepara la base de datos y el usuario de la aplicacion.
--
-- Este script corre UNA vez, cuando el datadir de MySQL esta vacio.
--
-- El usuario se crea con acceso desde cualquier host dentro de la red de
-- Docker ('%'), porque el contenedor backend llega a MySQL por el bridge
-- interno y su IP de origen no es predecible.
--
-- La base y el usuario tambien los crea la imagen oficial de MySQL a partir
-- de MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD (definidos en el .env del
-- grupo). Este script deja el GRANT explicito para que los permisos esten
-- garantizados aunque el usuario ya existiera.

CREATE DATABASE IF NOT EXISTS `getbela`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'getbela'@'%'
  IDENTIFIED BY 'getbela_dev_password';

ALTER USER 'getbela'@'%'
  IDENTIFIED BY 'getbela_dev_password';

GRANT ALL PRIVILEGES ON `getbela`.* TO 'getbela'@'%';

FLUSH PRIVILEGES;