-- MySQL dump 10.13  Distrib 5.5.29, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: bgpmon_analytics
-- ------------------------------------------------------
-- Server version	5.5.29-0ubuntu0.12.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `alarms`
--

DROP TABLE IF EXISTS `alarms`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `alarms` (
  `id` mediumint(9) NOT NULL AUTO_INCREMENT,
  `type` enum('email') NOT NULL DEFAULT 'email',
  `prefix` mediumint(9) NOT NULL,
  `owner` mediumint(9) NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `alarm_prefix_key` (`prefix`),
  KEY `alarm_owner_key` (`owner`),
  CONSTRAINT `alarm_owners_owner` FOREIGN KEY (`owner`) REFERENCES `owners` (`id`) ON DELETE CASCADE,
  CONSTRAINT `alarm_prefixes_prefix` FOREIGN KEY (`prefix`) REFERENCES `prefixes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `alarms`
--

LOCK TABLES `alarms` WRITE;
/*!40000 ALTER TABLE `alarms` DISABLE KEYS */;
INSERT INTO `alarms` VALUES (3,'email',1,1,0),(4,'email',2,1,0),(5,'email',3,1,0),(6,'email',4,1,0),(7,'email',5,1,1),(8,'email',6,1,0),(9,'email',7,1,0);
/*!40000 ALTER TABLE `alarms` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `alarmtriggers`
--

DROP TABLE IF EXISTS `alarmtriggers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `alarmtriggers` (
  `id` mediumint(9) NOT NULL AUTO_INCREMENT,
  `alarm` mediumint(9) NOT NULL,
  `triggertime` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `notified` tinyint(1) NOT NULL DEFAULT '0',
  `cleared` tinyint(1) NOT NULL DEFAULT '0',
  `type` varchar(10) DEFAULT NULL,
  `prefix` varchar(44) DEFAULT NULL,
  `path` varchar(120) DEFAULT NULL,
  `source` varchar(120) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `alarmtrigger_alarm_key` (`alarm`),
  KEY `alarmtrigger_prefix_key` (`prefix`),
  CONSTRAINT `alarmtrigger_alarms_alarm` FOREIGN KEY (`alarm`) REFERENCES `alarms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=29413 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `alarmtriggers`
--

LOCK TABLES `alarmtriggers` WRITE;
/*!40000 ALTER TABLE `alarmtriggers` DISABLE KEYS */;
/*!40000 ALTER TABLE `alarmtriggers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Temporary table structure for view `alarmtriggerview`
--

DROP TABLE IF EXISTS `alarmtriggerview`;
/*!50001 DROP VIEW IF EXISTS `alarmtriggerview`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `alarmtriggerview` (
  `alarmtype` tinyint NOT NULL,
  `email` tinyint NOT NULL,
  `alarmprefix` tinyint NOT NULL,
  `triggerperiodbegin` tinyint NOT NULL,
  `triggerperiodend` tinyint NOT NULL,
  `notified` tinyint NOT NULL,
  `cleared` tinyint NOT NULL,
  `announces` tinyint NOT NULL,
  `withdraws` tinyint NOT NULL,
  `prefix` tinyint NOT NULL,
  `path` tinyint NOT NULL,
  `source` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `owners`
--

DROP TABLE IF EXISTS `owners`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `owners` (
  `id` mediumint(9) NOT NULL AUTO_INCREMENT,
  `email` varchar(120) DEFAULT NULL,
  `web_pass` varchar(120) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `owners`
--

LOCK TABLES `owners` WRITE;
/*!40000 ALTER TABLE `owners` DISABLE KEYS */;
INSERT INTO `owners` VALUES (1,'david.freedman@uk.clara.net',NULL);
/*!40000 ALTER TABLE `owners` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `prefixes`
--

DROP TABLE IF EXISTS `prefixes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `prefixes` (
  `id` mediumint(9) NOT NULL AUTO_INCREMENT,
  `type` enum('as','ipv4','ipv6') NOT NULL DEFAULT 'ipv4',
  `prefix` varchar(44) NOT NULL,
  `matchop` varchar(2) DEFAULT NULL,
  `as_regexp` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `prefix_key` (`prefix`,`matchop`,`as_regexp`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `prefixes`
--

LOCK TABLES `prefixes` WRITE;
/*!40000 ALTER TABLE `prefixes` DISABLE KEYS */;
INSERT INTO `prefixes` VALUES (1,'ipv4','1.0.0.0/8','ms',NULL),(2,'ipv4','2.0.0.0/7','ms',NULL),(3,'ipv4','2.93.235.0/24','ms',NULL),(4,'ipv4','129.82.2.2','ms',NULL),(5,'ipv4','151.118.18.0/24','ms','_109_'),(6,'ipv4','194.150.174.0/23','ms',NULL),(7,'ipv4','100.200.200.0/24','ms',NULL);
/*!40000 ALTER TABLE `prefixes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Final view structure for view `alarmtriggerview`
--

/*!50001 DROP TABLE IF EXISTS `alarmtriggerview`*/;
/*!50001 DROP VIEW IF EXISTS `alarmtriggerview`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `alarmtriggerview` AS select `a`.`type` AS `alarmtype`,group_concat(distinct `o`.`email` separator ',') AS `email`,group_concat(distinct concat(`p`.`prefix`,' ',`p`.`matchop`,`p`.`as_regexp`) separator ',') AS `alarmprefix`,min(`at`.`triggertime`) AS `triggerperiodbegin`,max(`at`.`triggertime`) AS `triggerperiodend`,max(`at`.`notified`) AS `notified`,max(`at`.`cleared`) AS `cleared`,sum((`at`.`type` = 'ANNOUNCE')) AS `announces`,sum((`at`.`type` = 'WITHDRAW')) AS `withdraws`,group_concat(distinct `at`.`prefix` separator ',') AS `prefix`,group_concat(distinct `at`.`path` separator ',') AS `path`,group_concat(distinct `at`.`source` separator ',') AS `source` from (`owners` `o` left join (`prefixes` `p` left join (`alarms` `a` left join `alarmtriggers` `at` on((`at`.`alarm` = `a`.`id`))) on((`a`.`prefix` = `p`.`id`))) on((`a`.`owner` = `o`.`id`))) where (`at`.`id` is not null) group by (unix_timestamp(`at`.`triggertime`) DIV 300),`at`.`prefix` order by `at`.`triggertime` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2013-02-10 18:45:00
