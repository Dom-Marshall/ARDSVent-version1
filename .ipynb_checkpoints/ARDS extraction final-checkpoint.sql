{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW\n",
    "  `acf-research.project2.spo2fio2` AS\n",
    "SELECT\n",
    "  ie.subject_id,\n",
    "  ie.stay_id,\n",
    "  bg.charttime,\n",
    "  pao2fio2ratio\n",
    "FROM\n",
    "  `physionet-data.mimic_icu.icustays` ie\n",
    "LEFT JOIN\n",
    "  `physionet-data.mimic_derived.bg` bg\n",
    "ON\n",
    "  ie.subject_id = bg.subject_id\n",
    "  AND bg.specimen_pred = 'ART.'\n",
    "  AND bg.charttime >= ie.intime\n",
    "WHERE\n",
    "  pao2fio2ratio IS NOT NULL\n",
    "ORDER BY\n",
    "  stay_id"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ventilation` AS \n",
    "with ce as\n",
    "(\n",
    "  SELECT\n",
    "      ce.subject_id\n",
    "    , ce.stay_id\n",
    "    , ce.charttime\n",
    "    , itemid\n",
    "    -- TODO: clean\n",
    "    , value\n",
    "    , case\n",
    "        -- begin fio2 cleaning\n",
    "        when itemid = 223835\n",
    "        then\n",
    "            case\n",
    "                when valuenum >= 0.20 and valuenum <= 1\n",
    "                    then valuenum * 100\n",
    "                -- improperly input data - looks like O2 flow in litres\n",
    "                when valuenum > 1 and valuenum < 20\n",
    "                    then null\n",
    "                when valuenum >= 20 and valuenum <= 100\n",
    "                    then valuenum\n",
    "            ELSE NULL END\n",
    "        -- end of fio2 cleaning\n",
    "        -- begin peep cleaning\n",
    "        WHEN itemid in (220339, 224700)\n",
    "        THEN\n",
    "          CASE\n",
    "            WHEN valuenum > 100 THEN NULL\n",
    "            WHEN valuenum < 0 THEN NULL\n",
    "          ELSE valuenum END\n",
    "        -- end peep cleaning\n",
    "    ELSE valuenum END AS valuenum\n",
    "    , valueuom\n",
    "    , storetime\n",
    "  FROM `physionet-data.mimic_icu.chartevents` ce\n",
    "  where ce.value IS NOT NULL\n",
    "  AND ce.stay_id IS NOT NULL\n",
    "  AND ce.itemid IN\n",
    "  (\n",
    "      224688 -- Respiratory Rate (Set)\n",
    "    , 224689 -- Respiratory Rate (spontaneous)\n",
    "    , 224690 -- Respiratory Rate (Total)\n",
    "    , 224687 -- minute volume\n",
    "    , 224685, 224684, 224686 -- tidal volume\n",
    "    , 224696 -- PlateauPressure\n",
    "    , 220339, 224700 -- PEEP\n",
    "    , 223835 -- fio2\n",
    "    , 223849 -- vent mode\n",
    "    , 229314 -- vent mode (Hamilton)\n",
    "    , 223848 -- vent type\n",
    "  )\n",
    ")\n",
    "SELECT\n",
    "      subject_id\n",
    "    , MAX(stay_id) AS stay_id\n",
    "    , charttime\n",
    "    , MAX(CASE WHEN itemid = 224688 THEN valuenum ELSE NULL END) AS respiratory_rate_set\n",
    "    , MAX(CASE WHEN itemid = 224690 THEN valuenum ELSE NULL END) AS respiratory_rate_total\n",
    "    , MAX(CASE WHEN itemid = 224689 THEN valuenum ELSE NULL END) AS respiratory_rate_spontaneous\n",
    "    , MAX(CASE WHEN itemid = 224687 THEN valuenum ELSE NULL END) AS minute_volume\n",
    "    , MAX(CASE WHEN itemid = 224684 THEN valuenum ELSE NULL END) AS tidal_volume_set\n",
    "    , MAX(CASE WHEN itemid = 224685 THEN valuenum ELSE NULL END) AS tidal_volume_observed\n",
    "    , MAX(CASE WHEN itemid = 224686 THEN valuenum ELSE NULL END) AS tidal_volume_spontaneous\n",
    "    , MAX(CASE WHEN itemid = 224696 THEN valuenum ELSE NULL END) AS plateau_pressure\n",
    "    , MAX(CASE WHEN itemid in (220339, 224700) THEN valuenum ELSE NULL END) AS peep\n",
    "    , MAX(CASE WHEN itemid = 223835 THEN valuenum ELSE NULL END) AS fio2\n",
    "    , MAX(CASE WHEN itemid = 223849 THEN value ELSE NULL END) AS ventilator_mode\n",
    "    , MAX(CASE WHEN itemid = 229314 THEN value ELSE NULL END) AS ventilator_mode_hamilton\n",
    "    , MAX(CASE WHEN itemid = 223848 THEN value ELSE NULL END) AS ventilator_type\n",
    "FROM ce\n",
    "GROUP BY subject_id, charttime\n",
    "ORDER BY subject_id, charttime\n",
    "\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.sf_ratio` as\n",
    "WITH sp1 as\n",
    "(\n",
    "select  ce.subject_id\n",
    "  , ce.stay_id\n",
    "  , ce.charttime\n",
    "    -- max here is just used to group SpO2 by charttime\n",
    "    , max(case when valuenum <= 0 or valuenum > 100 then null else valuenum end) as spo2\n",
    "  FROM `physionet-data.mimic_icu.chartevents` ce\n",
    "  -- o2 sat\n",
    "  where ITEMID = 220277 -- O2 saturation pulseoxymetry\n",
    "  group by ce.subject_id, ce.stay_id, ce.charttime),\n",
    "sp2 as (\n",
    "SELECT v.subject_id, v.stay_id, v.charttime as vent_chartime, fio2, s.charttime as spo2_chartime, spo2, abs(timestamp_diff(v.charttime,  s.charttime, SECOND)) as time_rank,  \n",
    "FROM `acf-research.project2.ventilation` v\n",
    "LEFT JOIN sp1 as s\n",
    "ON v.stay_id = s.stay_id \n",
    "where spo2 is not null and fio2 is not null \n",
    "ORDER by subject_id),\n",
    "sp3 as\n",
    "(SELECT  subject_id, stay_id, vent_chartime, fio2, spo2_chartime, time_rank, spo2, RANK() OVER(PARTITION BY stay_id, vent_chartime ORDER BY time_rank ASC) as time_rank2\n",
    "FROM sp2\n",
    "WHERE time_rank < 3600),\n",
    "sp4 as\n",
    "(SELECT subject_id, stay_id, vent_chartime, fio2, spo2_chartime, time_rank, spo2, time_rank2\n",
    "FROM sp3 \n",
    "WHERE time_rank2 = 1)\n",
    "SELECT subject_id, stay_id, vent_chartime, fio2, spo2_chartime, spo2, (spo2/(fio2/100)) as SF\n",
    "FROM sp4 \n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ventilation_pf` as \n",
    "SELECT\n",
    " v.subject_id\n",
    " ,v.stay_id\n",
    " ,respiratory_rate_total\n",
    " ,respiratory_rate_spontaneous\n",
    " ,minute_volume\n",
    " ,tidal_volume_set\n",
    " ,tidal_volume_observed\n",
    " ,tidal_volume_spontaneous\n",
    " ,plateau_pressure\n",
    " ,peep\n",
    " ,fio2\n",
    " ,ventilator_mode\n",
    " ,ventilator_mode_hamilton\n",
    " ,ventilator_type\n",
    " ,pao2fio2ratio \n",
    " FROM `acf-research.project2.ventilation` as v\n",
    " LEFT JOIN `acf-research.project2.pao2fio2` AS p\n",
    " ON v.stay_id = p.stay_id\n",
    " WHERE p.charttime BETWEEN  (DATETIME_SUB(v.charttime, INTERVAL '2' HOUR)) and (DATETIME_ADD(v.charttime, INTERVAL '2' HOUR))\n",
    " ORDER BY v.subject_id, v.stay_id, v.charttime\n",
    "\n",
    "\n",
    "\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ARDS_id` as \n",
    "WITH pf1 as\n",
    "(\n",
    "    select v.subject_id, v.stay_id, v.charttime, pao2fio2ratio, RANK() OVER(PARTITION BY v.stay_id ORDER BY v.charttime ASC) as time_rank\n",
    "    FROM `acf-research.project2.ventilation_pf` v\n",
    "    WHERE pao2fio2ratio < 200),\n",
    "    pf2 as\n",
    "(\n",
    "SELECT p.subject_id, p.stay_id, p.charttime, p.pao2fio2ratio, p.time_rank\n",
    "FROM pf1 as p\n",
    "WHERE time_rank = 1),\n",
    "pf3 as\n",
    "(\n",
    "SELECT pf2.subject_id, pf2.stay_id, pf2.charttime, pf2.pao2fio2ratio, v2.charttime as further_event_charttime, v2.pao2fio2ratio as further_event_ratio\n",
    "FROM pf2 as pf2\n",
    "LEFT JOIN `acf-research.project2.ventilation_pf` v2\n",
    "on pf2.stay_id=v2.stay_id\n",
    "WHERE v2.pao2fio2ratio < 200\n",
    "AND v2.charttime  > pf2.charttime and  v2.charttime <= (DATETIME_ADD(v2.charttime, INTERVAL '24' HOUR)))\n",
    "SELECT distinct(pf3.stay_id), pf3.charttime, pf3.pao2fio2ratio\n",
    "from pf3 as pf3\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": []
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": []
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ARDS_id2` AS \n",
    "WITH first_vent as\n",
    "(SELECT v.stay_id, v.charttime, RANK() OVER(PARTITION BY v.stay_id ORDER BY v.charttime ASC) as time_rank\n",
    "FROM `acf-research.project2.ventilation` as v),\n",
    "second_vent as\n",
    "(SELECT v1.stay_id, v1.charttime, time_rank\n",
    "FROM first_vent as v1\n",
    "WHERE time_rank = 1)\n",
    "SELECT a.stay_id, a.charttime  \n",
    "FROM `acf-research.project2.ARDS_id` as a\n",
    "LEFT JOIN second_vent as v2\n",
    "ON a.stay_id=v2.stay_id\n",
    "WHERE a.charttime >= v2.charttime \n",
    "AND a.charttime <= DATETIME_ADD(v2.charttime, interval '7' DAY)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.vitalsigns` AS\n",
    "-- This query pivots the vital signs for the entire patient stay.\n",
    "-- Vital signs include heart rate, blood pressure, respiration rate, and temperature\n",
    "select\n",
    "    ce.subject_id\n",
    "  , ce.stay_id\n",
    "  , ce.charttime\n",
    "  , AVG(case when itemid in (220045) and valuenum > 0 and valuenum < 300 then valuenum else null end) as heart_rate\n",
    "  , AVG(case when itemid in (220179,220050) and valuenum > 0 and valuenum < 400 then valuenum else null end) as sbp\n",
    "  , AVG(case when itemid in (220180,220051) and valuenum > 0 and valuenum < 300 then valuenum else null end) as dbp\n",
    "  , AVG(case when itemid in (220052,220181,225312) and valuenum > 0 and valuenum < 300 then valuenum else null end) as mbp\n",
    "  , AVG(case when itemid = 220179 and valuenum > 0 and valuenum < 400 then valuenum else null end) as sbp_ni\n",
    "  , AVG(case when itemid = 220180 and valuenum > 0 and valuenum < 300 then valuenum else null end) as dbp_ni\n",
    "  , AVG(case when itemid = 220181 and valuenum > 0 and valuenum < 300 then valuenum else null end) as mbp_ni\n",
    "  , AVG(case when itemid in (220210,224690) and valuenum > 0 and valuenum < 70 then valuenum else null end) as resp_rate\n",
    "  , ROUND(\n",
    "      AVG(case when itemid in (223761) and valuenum > 70 and valuenum < 120 then (valuenum-32)/1.8 -- converted to degC in valuenum call\n",
    "              when itemid in (223762) and valuenum > 10 and valuenum < 50  then valuenum else null end)\n",
    "    , 2) as temperature\n",
    "  , MAX(CASE WHEN itemid = 224642 THEN value ELSE NULL END) AS temperature_site\n",
    "  , AVG(case when itemid in (220277) and valuenum > 0 and valuenum <= 100 then valuenum else null end) as spo2\n",
    "  , AVG(case when itemid in (225664,220621,226537) and valuenum > 0 then valuenum else null end) as glucose\n",
    "  FROM `physionet-data.mimic_icu.chartevents` ce\n",
    "  where ce.stay_id IS NOT NULL\n",
    "  and ce.itemid in\n",
    "  (\n",
    "    220045, -- Heart Rate\n",
    "    225309, -- ART BP Systolic\n",
    "    225310, -- ART BP Diastolic\n",
    "    225312, -- ART BP Mean\n",
    "    220050, -- Arterial Blood Pressure systolic\n",
    "    220051, -- Arterial Blood Pressure diastolic\n",
    "    220052, -- Arterial Blood Pressure mean\n",
    "    220179, -- Non Invasive Blood Pressure systolic\n",
    "    220180, -- Non Invasive Blood Pressure diastolic\n",
    "    220181, -- Non Invasive Blood Pressure mean\n",
    "    220210, -- Respiratory Rate\n",
    "    224690, -- Respiratory Rate (Total)\n",
    "    220277, -- SPO2, peripheral\n",
    "    -- GLUCOSE, both lab and fingerstick\n",
    "    225664, -- Glucose finger stick\n",
    "    220621, -- Glucose (serum)\n",
    "    226537, -- Glucose (whole blood)\n",
    "    -- TEMPERATURE\n",
    "    223762, -- \"Temperature Celsius\"\n",
    "    223761,  -- \"Temperature Fahrenheit\"\n",
    "    224642 -- Temperature Site\n",
    "    -- 226329 -- Blood Temperature CCO (C)\n",
    ")\n",
    "group by ce.subject_id, ce.stay_id, ce.charttime\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "\n",
    "--- check that the first P/F ratio < 200 is within 7 days of ICU admission \n",
    "\n",
    "WITH first_vent as\n",
    "(SELECT v.subject_id, v.stay_id, v.charttime, RANK() OVER(PARTITION BY v.stay_id ORDER BY v.charttime ASC) as time_rank\n",
    "FROM `acf-research.project2.ventilation` as v),\n",
    "second_vent as\n",
    "(SELECT v1.subject_id, v1.stay_id, v1.charttime, time_rank\n",
    "FROM first_vent as v1\n",
    "WHERE time_rank = 1),\n",
    "third_vent as\n",
    "(SELECT v2.subject_id, a.stay_id, a.charttime  \n",
    "FROM `acf-research.project2.ARDS_id` as a\n",
    "LEFT JOIN second_vent as v2\n",
    "ON a.stay_id=v2.stay_id\n",
    "WHERE a.charttime >= v2.charttime \n",
    "AND a.charttime <= DATETIME_ADD(v2.charttime, interval '7' DAY))\n",
    "Select v3.stay_id, v3.charttime \n",
    "FROM third_vent as v3\n",
    "LEFT JOIN  `acf-research.project2.age` a2\n",
    "ON a2.subject_id=v3.subject_id\n",
    "AND a2.age >= 18\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "--- identify cohort who have pf< 200 and then subequent pf < 200 in next 24 hours - 17286 (unique stay_id)\n",
    "CREATE VIEW `acf-research.project2.ARDS_id1` as\n",
    "WITH pf1 as\n",
    "(\n",
    "    select v.subject_id, v.stay_id, v.charttime, pao2fio2ratio, RANK() OVER(PARTITION BY v.subject_id ORDER BY v.charttime ASC) as time_rank\n",
    "    FROM `acf-research.project2.ventilation_pf` v\n",
    "    WHERE pao2fio2ratio < 200),\n",
    "    pf2 as\n",
    "(\n",
    "SELECT p.subject_id, p.stay_id, p.charttime, p.pao2fio2ratio, p.time_rank\n",
    "FROM pf1 as p\n",
    "WHERE time_rank = 1),\n",
    "pf3 as\n",
    "(\n",
    "SELECT pf2.subject_id, pf2.stay_id, pf2.charttime, pf2.pao2fio2ratio, v2.charttime as further_event_charttime, v2.pao2fio2ratio as further_event_ratio\n",
    "FROM pf2 as pf2\n",
    "LEFT JOIN `acf-research.project2.ventilation_pf` v2\n",
    "on pf2.stay_id=v2.stay_id\n",
    "WHERE v2.pao2fio2ratio < 200\n",
    "AND v2.charttime  > pf2.charttime and  v2.charttime <= (DATETIME_ADD(v2.charttime, INTERVAL '24' HOUR)))\n",
    "SELECT distinct(pf3.stay_id), pf3.subject_id, pf3.charttime, pf3.pao2fio2ratio\n",
    "from pf3 as pf3\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "--- check that the first P/F ratio <200 is within 7 days of ICU admission \n",
    "CREATE VIEW `acf-research.project2.ARDS_id2` as\n",
    "WITH first_vent as\n",
    "(SELECT v.subject_id, v.stay_id, v.charttime, RANK() OVER(PARTITION BY v.stay_id ORDER BY v.charttime ASC) as time_rank\n",
    "FROM `acf-research.project2.ventilation` as v),\n",
    "second_vent as\n",
    "(SELECT v1.subject_id, v1.stay_id, v1.charttime, time_rank\n",
    "FROM first_vent as v1\n",
    "WHERE time_rank = 1)\n",
    "SELECT a.subject_id, a.stay_id, a.charttime  \n",
    "FROM `acf-research.project2.ARDS_id1` as a\n",
    "LEFT JOIN second_vent as v2\n",
    "ON a.stay_id=v2.stay_id\n",
    "WHERE a.charttime >= v2.charttime \n",
    "AND a.charttime <= DATETIME_ADD(v2.charttime, interval '7' DAY)\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ARDS_id3` as\n",
    "WITH over18 as \n",
    "(SELECT i.subject_id, i.hadm_id, i.stay_id, i.admission_age\n",
    "FROM `acf-research.project2.icustay_detail` i\n",
    "WHERE i.admission_age >= 18)\n",
    "SELECT DISTINCT(v.subject_id), v.stay_id, v.charttime\n",
    "FROM `acf-research.project2.ARDS_id2` v\n",
    "INNER JOIN over18 o\n",
    "ON v.stay_id=o.stay_id\n",
    "\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "----CREATE VIEW `acf-research.project2.ards_firstbg` as\n",
    "With v0 as\n",
    "(\n",
    "    select a.subject_id, a.stay_id, a.charttime, v.tidal_volume_set, v.plateau_pressure, v.PEEP, (v.plateau_pressure - v.PEEP) as driving_pressure,\n",
    "    abs(timestamp_diff(a.charttime,  v.charttime, SECOND)) as time_rank\n",
    "    FROM `acf-research.project2.ARDS_id3` a\n",
    "    LEFT JOIN `acf-research.project2.ventilation` v\n",
    "    ON a.subject_id=v.subject_id\n",
    "    WHERE tidal_volume_spontaneous is null AND tidal_volume_set is not null AND plateau_pressure is not null AND plateau_pressure != 0),\n",
    "v1 as\n",
    "(\n",
    "select *\n",
    "from v0 \n",
    "where v0.driving_pressure != 0 and v0.driving_pressure is not null),\n",
    "v2 as\n",
    "(\n",
    "    SELECT v1.subject_id, v1.stay_id, v1.charttime, v1.tidal_volume_set, v1.plateau_pressure, v1.PEEP, v1.time_rank, v1.driving_pressure,\n",
    "     RANK() OVER(PARTITION BY v1.stay_id ORDER BY v1.time_rank ASC) as time_rank2\n",
    "    FROM v1),\n",
    "v3 as \n",
    "(\n",
    "SELECT v2.subject_id, v2.stay_id, v2.charttime, v2.tidal_volume_set, v2.plateau_pressure, v2.PEEP, v2.time_rank, v2.driving_pressure\n",
    "FROM v2\n",
    "WHERE v2.time_rank2 = 1)\n",
    "select v3.subject_id, v3.stay_id, v3.charttime, v3.tidal_volume_set as tv_entry, v3.plateau_pressure as plateau_pressure_entry, v3.PEEP as PEEP_entry, v3.time_rank,\n",
    " v3.driving_pressure as driving_pressure_entry, (v3.tidal_volume_set/ v3.driving_pressure) AS static_compliance\n",
    "FROM v3\n",
    "WHERE time_rank < 21600\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "----CREATE VIEW `acf-research.project2.ards_firstvent` as\n",
    "With v0 as\n",
    "(\n",
    "    select a.subject_id, a.stay_id, a.charttime, v.tidal_volume_set, v.plateau_pressure, v.PEEP, (v.plateau_pressure - v.PEEP) as driving_pressure,\n",
    "    abs(timestamp_diff(a.charttime,  v.charttime, SECOND)) as time_rank\n",
    "    FROM `acf-research.project2.ARDS_id3` a\n",
    "    LEFT JOIN `acf-research.project2.ventilation` v\n",
    "    ON a.subject_id=v.subject_id\n",
    "    WHERE tidal_volume_spontaneous is null AND tidal_volume_set is not null AND plateau_pressure is not null AND plateau_pressure != 0),\n",
    "v1 as\n",
    "(\n",
    "select *\n",
    "from v0 \n",
    "where v0.driving_pressure != 0 and v0.driving_pressure is not null),\n",
    "v2 as\n",
    "(\n",
    "    SELECT v1.subject_id, v1.stay_id, v1.charttime, v1.tidal_volume_set, v1.plateau_pressure, v1.PEEP, v1.time_rank, v1.driving_pressure,\n",
    "     RANK() OVER(PARTITION BY v1.stay_id ORDER BY v1.time_rank ASC) as time_rank2\n",
    "    FROM v1),\n",
    "v3 as \n",
    "(\n",
    "SELECT v2.subject_id, v2.stay_id, v2.charttime, v2.tidal_volume_set, v2.plateau_pressure, v2.PEEP, v2.time_rank, v2.driving_pressure\n",
    "FROM v2\n",
    "WHERE v2.time_rank2 = 1)\n",
    "select v3.subject_id, v3.stay_id, v3.charttime, v3.tidal_volume_set as tv_entry, v3.plateau_pressure as plateau_pressure_entry, v3.PEEP as PEEP_entry, v3.time_rank,\n",
    " v3.driving_pressure as driving_pressure_entry, (v3.tidal_volume_set/ v3.driving_pressure) AS static_compliance\n",
    "FROM v3\n",
    "WHERE time_rank < 43200\n",
    "\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ards_pre_ards_vent_time` as\n",
    "WITH v1 as\n",
    "(\n",
    "SELECT v.subject_id, v.stay_id, min(v.charttime) as starttime\n",
    "FROM `acf-research.project2.ventilation` v\n",
    "GROUP BY v.subject_id, v.stay_id\n",
    ")\n",
    "SELECT a.subject_id, a.stay_id, a.charttime, abs(timestamp_diff(v1.starttime,  a.charttime, HOUR)) as pre_vent\n",
    "FROM `acf-research.project2.ARDS_id3` as a\n",
    "LEFT JOIN v1 as v1\n",
    "ON a.stay_id = v1.stay_id\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.day1_fio2_paco2` as\n",
    "WITH f1 as\n",
    "(\n",
    "select  ce.subject_id\n",
    "  , ce.stay_id\n",
    "  , ce.charttime\n",
    "    -- max here is just used to group SpO2 by charttime\n",
    "    , max(case when valuenum <= 0 or valuenum > 100 then null else valuenum end) as fio2\n",
    "  FROM `physionet-data.mimic_icu.chartevents` ce\n",
    "  -- o2 sat\n",
    "  where ITEMID = 223835  -- FIO2\n",
    "    group by ce.subject_id, ce.stay_id, ce.charttime),\n",
    "paco2 as\n",
    "(\n",
    "    SELECT a.subject_id, a.stay_id, a.charttime, avg(bg.pco2) as co2_d1\n",
    "FROM `acf-research.project2.ARDS_id3` as a\n",
    "LEFT JOIN `acf-research.project2.bg` as bg\n",
    "ON a.subject_id=bg.subject_id\n",
    "WHERE bg.specimen_pred = 'ART.'\n",
    "    AND  bg.charttime >= a.charttime \n",
    "    AND bg.charttime <= DATETIME_ADD(a.charttime, INTERVAL '24' HOUR)     \n",
    "GROUP BY a.subject_id, a.stay_id, a.charttime\n",
    ")\n",
    "SELECT p.subject_id, p.stay_id, p.charttime, round(p.co2_d1, 1) as d1_pco2, round(avg(f1.fio2), 0) as d1_fio2\n",
    "FROM paco2 p\n",
    "LEFT JOIN f1\n",
    "ON p.subject_id=f1.subject_id\n",
    "GROUP BY p.subject_id, p.stay_id, p.charttime, p.co2_d1"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ards_d1_vent` as\n",
    "\n",
    "WITH ventilation1 as\n",
    "(SELECT v.subject_id, v.stay_id, v.charttime, v.respiratory_rate_set as rr, v.tidal_volume_set as tv, v.plateau_pressure, v.peep, (v.plateau_pressure - v.peep) as driving_pressure\n",
    "FROM `acf-research.project2.ventilation` v\n",
    "WHERE  tidal_volume_spontaneous is null AND tidal_volume_set is not null),\n",
    "ventilation2 as\n",
    "(SELECT v1.subject_id, v1.stay_id, v1.charttime, v1.tv, v1.rr, v1.plateau_pressure, v1.peep, v1.driving_pressure, (tv/v1.driving_pressure ) as static_compliance\n",
    "FROM ventilation1 as v1\n",
    "WHERE  plateau_pressure is not null AND plateau_pressure != 0 and v1.driving_pressure !=0),\n",
    "ventilaton3 as\n",
    "(SELECT a.subject_id, a.stay_id, a.charttime, round(avg(v1.rr),0) as d1_rr, round(avg(v1.tv), 0) as d1_tv, round(avg(v1.peep), 0) as d1_peep\n",
    "FROM `acf-research.project2.ARDS_id3` as a \n",
    "LEFT JOIN ventilation1  as v1\n",
    "ON a.subject_id=v1.subject_id\n",
    "WHERE  v1.charttime >= a.charttime \n",
    "    AND v1.charttime <= DATETIME_ADD(a.charttime, INTERVAL '24' HOUR)  \n",
    "GROUP BY a.subject_id, a.stay_id, a.charttime)\n",
    "SELECT v3.subject_id, v3.stay_id, v3.charttime, v3.d1_rr, v3.d1_tv, v3.d1_PEEP, round(avg(v2.driving_pressure), 0) as d1_driving_pressure, round(avg(v2.static_compliance), 0) as d1_static_compliance\n",
    "FROM ventilaton3 as v3\n",
    "LEFT JOIN ventilation2 as v2\n",
    "ON v3.subject_id=v2.subject_id\n",
    "WHERE  v2.charttime >= v3.charttime \n",
    "    AND v2.charttime <= DATETIME_ADD(v3.charttime, INTERVAL '24' HOUR)  \n",
    "GROUP BY v3.subject_id, v3.stay_id, v3.charttime, v3.d1_rr, v3.d1_tv, v3.d1_PEEP\n",
    "\n",
    "\n"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "CREATE VIEW `acf-research.project2.ards_tbl_analysis` as\n",
    "WITH step1 AS\n",
    "(select a.subject_id, a.stay_id, d.admission_age, d.hospital_expire_flag, d.gender, d.los_icu\n",
    "FROM `acf-research.project2.ARDS_id3` a\n",
    "LEFT JOIN `acf-research.project2.icustay_detail` d\n",
    "ON a.stay_id=d.stay_id\n",
    "),\n",
    "step2 as\n",
    "(\n",
    "SELECT s1.subject_id, s1.stay_id, s1.admission_age, s1.hospital_expire_flag, s1.gender, s1.los_icu, saps.sapsii, saps.sapsii_prob\n",
    "FROM step1 s1\n",
    "LEFT JOIN `acf-research.project2.sapsii` as saps\n",
    "ON s1.stay_id=saps.stay_id\n",
    "),\n",
    "step3 as\n",
    "(SELECT s2.subject_id, s2.stay_id, s2.admission_age, s2.hospital_expire_flag, s2.gender, s2.los_icu, s2.sapsii, s2.sapsii_prob, p.pf_entry, p.pH_entry\n",
    "FROM step2 as s2\n",
    "LEFT JOIN `acf-research.project2.ards_firstbg` as p\n",
    "ON s2.stay_id=p.stay_id),\n",
    "step4 as \n",
    "(\n",
    "SELECT s3.subject_id, s3.stay_id, s3.admission_age, s3.hospital_expire_flag, s3.gender, s3.los_icu, s3.sapsii, s3.sapsii_prob, s3.pf_entry, s3.pH_entry, \n",
    "f1.tv_entry, f1.driving_pressure_entry, f1.static_compliance as static_compliance_entry\n",
    "FROM step3 as s3\n",
    "LEFT JOIN `acf-research.project2.ards_firstvent` as f1\n",
    "ON s3.stay_id=f1.stay_id\n",
    "),\n",
    "step5 as\n",
    "(SELECT s4.subject_id, s4.stay_id, s4.admission_age, s4.hospital_expire_flag, s4.gender, s4.los_icu, s4.sapsii, s4.sapsii_prob, s4.pf_entry, s4.pH_entry, \n",
    "s4.tv_entry, s4.driving_pressure_entry, s4.static_compliance_entry, g.d1_pco2, g.d1_fio2\n",
    "FROM step4 as s4\n",
    "LEFT JOIN `acf-research.project2.day1_fio2_paco2` as g\n",
    "ON s4.stay_id=g.stay_id),\n",
    "step6 as\n",
    "( \n",
    "SELECT s5.subject_id, s5.stay_id, s5.admission_age, s5.hospital_expire_flag, s5.gender, s5.los_icu, s5.sapsii, s5.sapsii_prob, s5.pf_entry, s5.pH_entry, \n",
    "s5.tv_entry, s5.driving_pressure_entry, s5.static_compliance_entry, s5.d1_pco2, s5.d1_fio2, d1.d1_tv, d1.d1_rr, d1.d1_PEEP, d1.d1_plateau_preasure as d1_plateau_pressure,\n",
    "d1.d1_driving_pressure, d1.d1_static_compliance\n",
    "FROM step5 as s5\n",
    "LEFT JOIN `acf-research.project2.ards_d1_vent` as d1\n",
    "ON s5.stay_id=d1.stay_id\n",
    ")\n",
    "SELECT s6.subject_id, s6.stay_id, s6.admission_age, s6.hospital_expire_flag, s6.gender, s6.los_icu, s6.sapsii, s6.sapsii_prob, pv.pre_vent, s6.pf_entry, s6.pH_entry, \n",
    "s6.tv_entry, s6.driving_pressure_entry, s6.static_compliance_entry, s6.d1_pco2, s6.d1_fio2, s6.d1_tv, s6.d1_rr, s6.d1_PEEP, d1_plateau_pressure,\n",
    "s6.d1_driving_pressure, s6.d1_static_compliance\n",
    "FROM step6 as s6\n",
    "LEFT JOIN `acf-research.project2.ards_pre_ards_vent_time` as pv\n",
    "ON s6.stay_id=pv.stay_id\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "",
   "name": ""
  },
  "language_info": {
   "name": ""
  }
 },
 "nbformat": 4,
 "nbformat_minor": 2
}
