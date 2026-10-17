--
-- PostgreSQL database dump
--

\restrict nVYzhkzkAej25U6KuSa5Kwo9Z2mEuDV7xJIORZDIf9EmqBseHKQL9i6kQLeR7vD

-- Dumped from database version 15.17
-- Dumped by pg_dump version 18.4 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: schema_3; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA schema_3;


--
-- Name: proposal_type; Type: TYPE; Schema: schema_3; Owner: -
--

CREATE TYPE schema_3.proposal_type AS ENUM (
    'RFP (Proposals)',
    'Rosters'
);


--
-- Name: get_winning_variant(integer, character varying); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.get_winning_variant(p_cmpid integer, p_criteria character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  winner_id INT;
BEGIN
  IF p_criteria = 'click_rate' THEN
    SELECT id INTO winner_id
    FROM schema_3.campaign_variants
    WHERE cmpid = p_cmpid AND sent > 0
    ORDER BY click_rate DESC, is_control DESC  -- Control wins ties
    LIMIT 1;
  ELSE
    SELECT id INTO winner_id
    FROM schema_3.campaign_variants
    WHERE cmpid = p_cmpid AND sent > 0
    ORDER BY open_rate DESC, is_control DESC  -- Control wins ties
    LIMIT 1;
  END IF;
  
  RETURN winner_id;
END;
$$;


--
-- Name: update_cokl_inspection_timestamp(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.update_cokl_inspection_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: update_pmis_access_timestamp(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.update_pmis_access_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: update_variant_rates(integer); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.update_variant_rates(p_variant_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE schema_3.campaign_variants
  SET 
    open_rate = CASE WHEN sent > 0 THEN ROUND((opens::DECIMAL / sent) * 100, 2) ELSE 0 END,
    click_rate = CASE WHEN sent > 0 THEN ROUND((clicks::DECIMAL / sent) * 100, 2) ELSE 0 END
  WHERE id = p_variant_id;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: dashboard; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.dashboard (
    dashboard_id integer NOT NULL,
    dashboard_name character varying,
    user_id integer,
    cards_id integer[],
    available_cards integer[]
);


--
-- Name: Dashboard_dashboard_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3."Dashboard_dashboard_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: Dashboard_dashboard_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3."Dashboard_dashboard_id_seq" OWNED BY schema_3.dashboard.dashboard_id;


--
-- Name: ttm; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ttm (
    ttm_id bigint NOT NULL,
    data text,
    employee_info text,
    designations text
);


--
-- Name: TTM_ttm_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3."TTM_ttm_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: TTM_ttm_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3."TTM_ttm_id_seq" OWNED BY schema_3.ttm.ttm_id;


--
-- Name: ab_email_events; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ab_email_events (
    id integer NOT NULL,
    cmpid integer NOT NULL,
    variant_id integer,
    contact_email character varying(255) NOT NULL,
    event_type character varying(20) NOT NULL,
    event_data jsonb,
    ses_message_id character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ab_email_events_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.ab_email_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_email_events_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.ab_email_events_id_seq OWNED BY schema_3.ab_email_events.id;


--
-- Name: automation_emails; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.automation_emails (
    id integer NOT NULL,
    enrollment_id integer NOT NULL,
    step_key character varying(50) NOT NULL,
    template_id integer NOT NULL,
    ses_message_id character varying(255),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT automation_emails_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('sent'::character varying)::text, ('delivered'::character varying)::text, ('opened'::character varying)::text, ('clicked'::character varying)::text])))
);


--
-- Name: automation_emails_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.automation_emails_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.automation_emails_id_seq OWNED BY schema_3.automation_emails.id;


--
-- Name: automation_enrollments; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.automation_enrollments (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    audience_id integer NOT NULL,
    contact_email character varying(255) NOT NULL,
    current_step character varying(50) DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    waiting_until timestamp with time zone,
    waiting_for character varying(50),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    paused_from character varying(20),
    CONSTRAINT automation_enrollments_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('waiting'::character varying)::text, ('paused'::character varying)::text, ('completed'::character varying)::text, ('exited'::character varying)::text])))
);


--
-- Name: automation_enrollments_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.automation_enrollments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_enrollments_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.automation_enrollments_id_seq OWNED BY schema_3.automation_enrollments.id;


--
-- Name: automation_flows; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.automation_flows (
    id integer NOT NULL,
    cmpid integer NOT NULL,
    name character varying(50) DEFAULT 'drip'::character varying NOT NULL,
    flow_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying(20) DEFAULT 'draft'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT automation_flows_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('active'::character varying)::text, ('paused'::character varying)::text, ('completed'::character varying)::text])))
);


--
-- Name: automation_flows_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.automation_flows_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.automation_flows_id_seq OWNED BY schema_3.automation_flows.id;


--
-- Name: automation_logs; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.automation_logs (
    id integer NOT NULL,
    enrollment_id integer NOT NULL,
    step_key character varying(50) NOT NULL,
    action character varying(50) NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: automation_logs_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.automation_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.automation_logs_id_seq OWNED BY schema_3.automation_logs.id;


--
-- Name: campaign; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign (
    id integer NOT NULL,
    name text,
    description text,
    campaign_type character varying(50),
    status character varying(50),
    sender_name text,
    sender_email text,
    reply_to_email text,
    subject text,
    template_id integer,
    ab_testing boolean DEFAULT false,
    ab_test_type character varying(50),
    ab_metric character varying(50) DEFAULT 'open_rate'::character varying,
    ab_status character varying(50) DEFAULT 'none'::character varying,
    ab_test_started_at timestamp without time zone,
    ab_test_ends_at timestamp without time zone,
    ab_test_duration_minutes integer,
    ab_test_sample_percentage integer,
    ab_split_a integer DEFAULT 50,
    ab_split_b integer DEFAULT 50,
    schedule_at timestamp without time zone,
    send_immediately boolean DEFAULT false,
    winner_variant_id integer,
    created_by integer,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone,
    campaign_settings jsonb,
    flow jsonb,
    label jsonb,
    paused_from character varying(50)
);


--
-- Name: campaign_audience; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign_audience (
    id integer NOT NULL,
    cmpid integer NOT NULL,
    contact_email character varying(255) NOT NULL,
    contact_name character varying(255) DEFAULT NULL::character varying,
    contact_type character varying(20) DEFAULT NULL::character varying,
    contact_id integer,
    contact_data jsonb,
    variant_id integer,
    is_test_group boolean DEFAULT false,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    queued_at timestamp without time zone,
    sent_at timestamp without time zone,
    delivered_at timestamp without time zone,
    opened_at timestamp without time zone,
    clicked_at timestamp without time zone,
    ses_message_id character varying(255) DEFAULT NULL::character varying,
    error_message text,
    retry_count integer DEFAULT 0
);


--
-- Name: campaign_audience_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_audience_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_audience_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_audience_id_seq OWNED BY schema_3.campaign_audience.id;


--
-- Name: campaign_content_calendar; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign_content_calendar (
    id integer NOT NULL,
    content_category text,
    type text,
    status text,
    date date,
    assigned_to json,
    social_media json,
    title text,
    caption text,
    reference text,
    description text,
    notes text
);


--
-- Name: campaign_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_id_seq OWNED BY schema_3.campaign_content_calendar.id;


--
-- Name: campaign_id_seq1; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_id_seq1; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_id_seq1 OWNED BY schema_3.campaign.id;


--
-- Name: campaign_recipient; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign_recipient (
    id integer NOT NULL,
    campaign_id integer NOT NULL,
    people_id integer,
    organization_id integer,
    recipient_type character varying(20) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    variant_id integer,
    is_test_group boolean DEFAULT false,
    ses_message_id character varying(255),
    opened_at timestamp without time zone,
    clicked_at timestamp without time zone,
    bounce_type character varying(10),
    complaint boolean DEFAULT false,
    complaint_at timestamp without time zone,
    bounce_subtype character varying(50),
    bounced_at timestamp without time zone,
    complaint_type character varying(50),
    delivered_at timestamp without time zone,
    delivery_time_ms integer,
    failure_reason text,
    open_ip character varying(45),
    open_user_agent text,
    open_count integer DEFAULT 0,
    click_ip character varying(45),
    click_user_agent text,
    clicked_link text,
    click_count integer DEFAULT 0,
    country character varying(100),
    city character varying(100),
    device_type character varying(50),
    email_client character varying(100),
    CONSTRAINT campaign_recipient_recipient_type_check CHECK (((recipient_type)::text = ANY (ARRAY[('people'::character varying)::text, ('organization'::character varying)::text]))),
    CONSTRAINT campaign_recipient_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('sent'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: campaign_recipient_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_recipient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_recipient_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_recipient_id_seq OWNED BY schema_3.campaign_recipient.id;


--
-- Name: campaign_senders_email; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign_senders_email (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    created_by character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: campaign_senders_email_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_senders_email_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_senders_email_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_senders_email_id_seq OWNED BY schema_3.campaign_senders_email.id;


--
-- Name: campaign_variants; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.campaign_variants (
    id integer NOT NULL,
    cmpid integer NOT NULL,
    variant_key character varying(5),
    variant_name character varying(100) DEFAULT NULL::character varying,
    subject character varying(255) DEFAULT NULL::character varying,
    htmlcontent text,
    textcontent text,
    templateid integer,
    template_s3_url text,
    sent integer DEFAULT 0,
    delivered integer DEFAULT 0,
    opens integer DEFAULT 0,
    clicks integer DEFAULT 0,
    bounces integer DEFAULT 0,
    complaints integer DEFAULT 0,
    open_rate numeric(5,2) DEFAULT 0,
    click_rate numeric(5,2) DEFAULT 0,
    is_control boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    traffic_percentage integer
);


--
-- Name: campaign_variants_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.campaign_variants_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaign_variants_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.campaign_variants_id_seq OWNED BY schema_3.campaign_variants.id;


--
-- Name: city_tender_templates; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.city_tender_templates (
    id integer NOT NULL,
    city character varying(50) NOT NULL,
    sections jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: city_tender_templates_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.city_tender_templates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: city_tender_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.city_tender_templates_id_seq OWNED BY schema_3.city_tender_templates.id;


--
-- Name: client_email_region_pms; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.client_email_region_pms (
    id integer NOT NULL,
    region_id integer NOT NULL,
    name character varying(255),
    email character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: client_email_region_pms_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.client_email_region_pms_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_email_region_pms_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.client_email_region_pms_id_seq OWNED BY schema_3.client_email_region_pms.id;


--
-- Name: client_email_regions; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.client_email_regions (
    region_id integer NOT NULL,
    region character varying(100) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: client_email_regions_region_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.client_email_regions_region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_email_regions_region_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.client_email_regions_region_id_seq OWNED BY schema_3.client_email_regions.region_id;


--
-- Name: client_email_templates; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.client_email_templates (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    subject character varying(500) NOT NULL,
    body text NOT NULL,
    placeholders text[] DEFAULT '{}'::text[],
    region_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    region character varying(100) DEFAULT 'Malaysia'::character varying
);


--
-- Name: client_email_templates_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.client_email_templates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_email_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.client_email_templates_id_seq OWNED BY schema_3.client_email_templates.id;


--
-- Name: cokl_inspection_deficiencies; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.cokl_inspection_deficiencies (
    id integer NOT NULL,
    inspection_id integer NOT NULL,
    present boolean DEFAULT false,
    category character varying(100),
    severity character varying(50),
    station character varying(50),
    assigned_to character varying(100),
    description text,
    due_date date,
    photo_ref character varying(200),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_severity CHECK (((severity)::text = ANY ((ARRAY['Low'::character varying, 'Medium'::character varying, 'High'::character varying, 'Critical'::character varying])::text[])))
);


--
-- Name: TABLE cokl_inspection_deficiencies; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON TABLE schema_3.cokl_inspection_deficiencies IS 'Deficiencies/issues identified during site inspections';


--
-- Name: cokl_inspection_deficiencies_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.cokl_inspection_deficiencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cokl_inspection_deficiencies_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.cokl_inspection_deficiencies_id_seq OWNED BY schema_3.cokl_inspection_deficiencies.id;


--
-- Name: cokl_inspection_driveways; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.cokl_inspection_driveways (
    id integer NOT NULL,
    inspection_id integer NOT NULL,
    uid character varying(100) NOT NULL,
    surface_type character varying(50),
    status character varying(50),
    completion_date date,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    longitude double precision,
    latitude double precision,
    address text,
    CONSTRAINT chk_driveway_status CHECK (((status IS NULL) OR ((status)::text = ANY (ARRAY['Pending'::text, 'In Progress'::text, 'Completed'::text, 'Hold – Weather'::text, 'Hold – Inspector'::text, 'Partially Reinstated'::text, 'Not Required'::text, 'N/A'::text]))))
);


--
-- Name: TABLE cokl_inspection_driveways; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON TABLE schema_3.cokl_inspection_driveways IS 'Driveway information associated with site inspections';


--
-- Name: cokl_inspection_driveways_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.cokl_inspection_driveways_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cokl_inspection_driveways_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.cokl_inspection_driveways_id_seq OWNED BY schema_3.cokl_inspection_driveways.id;


--
-- Name: cokl_no_report_inspections; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.cokl_no_report_inspections (
    id integer NOT NULL,
    entry_id character varying(100) NOT NULL,
    visit_date date NOT NULL,
    visit_time time without time zone NOT NULL,
    inspector character varying(100) NOT NULL,
    area_code character varying(50),
    operating_area character varying(100),
    road_name character varying(200) NOT NULL,
    jde_project_id character varying(50),
    no_report_reason text NOT NULL,
    notes text,
    weather character varying(50),
    photos_taken character varying(20),
    submitted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    platform character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(100),
    updated_by character varying(100)
);


--
-- Name: cokl_no_report_inspections_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.cokl_no_report_inspections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cokl_no_report_inspections_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.cokl_no_report_inspections_id_seq OWNED BY schema_3.cokl_no_report_inspections.id;


--
-- Name: cokl_site_inspections; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.cokl_site_inspections (
    id integer NOT NULL,
    entry_id character varying(100) NOT NULL,
    inspection_date date NOT NULL,
    inspection_time time without time zone NOT NULL,
    inspector character varying(100) NOT NULL,
    area_code character varying(50),
    operating_area character varying(100),
    road_name character varying(200),
    jde_project_id character varying(50) NOT NULL,
    total_road_length_m numeric(10,2),
    task_type character varying(100),
    task_status character varying(50),
    pct_complete numeric(5,2),
    station_start character varying(50),
    station_end character varying(50),
    task_actual_start date,
    task_actual_finish date,
    forecast_finish date,
    incurred_cost_today numeric(12,2),
    qty_hma_overlay_t numeric(10,2),
    qty_hma_padding_t numeric(10,2),
    qty_rap_t numeric(10,2),
    qty_pulverizing_m numeric(10,2),
    qty_grading_m2 numeric(10,2),
    milestone_reached boolean DEFAULT false,
    milestone_id character varying(50),
    new_risk_flag boolean DEFAULT false,
    new_risk_description text,
    weather character varying(50),
    photos_taken character varying(20),
    site_notes text,
    submitted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    submission_status character varying(30) DEFAULT 'submitted'::character varying,
    platform character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(100),
    updated_by character varying(100),
    qty_shouldering_t numeric,
    CONSTRAINT chk_pct_complete CHECK (((pct_complete >= (0)::numeric) AND (pct_complete <= (100)::numeric))),
    CONSTRAINT chk_submission_status CHECK (((submission_status)::text = ANY ((ARRAY['draft'::character varying, 'submitted'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: TABLE cokl_site_inspections; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON TABLE schema_3.cokl_site_inspections IS 'Main table for COKL construction site inspection records';


--
-- Name: COLUMN cokl_site_inspections.entry_id; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.cokl_site_inspections.entry_id IS 'Unique entry identifier in format: YYYYMMDD-INSPECTOR-ROAD';


--
-- Name: COLUMN cokl_site_inspections.jde_project_id; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.cokl_site_inspections.jde_project_id IS 'JD Edwards project identifier (foreign key)';


--
-- Name: COLUMN cokl_site_inspections.pct_complete; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.cokl_site_inspections.pct_complete IS 'Task completion percentage (0-100)';


--
-- Name: COLUMN cokl_site_inspections.milestone_reached; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.cokl_site_inspections.milestone_reached IS 'Flag indicating if a project milestone was reached';


--
-- Name: COLUMN cokl_site_inspections.new_risk_flag; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.cokl_site_inspections.new_risk_flag IS 'Flag indicating new risk identified during inspection';


--
-- Name: cokl_site_inspections_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.cokl_site_inspections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cokl_site_inspections_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.cokl_site_inspections_id_seq OWNED BY schema_3.cokl_site_inspections.id;


--
-- Name: daily_sheet_update; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.daily_sheet_update (
    id integer NOT NULL,
    priority text,
    project_name text,
    status text,
    department text,
    sub_department text,
    project_category text,
    task text,
    timeline text,
    created_at timestamp with time zone DEFAULT now(),
    today_update text,
    next_steps text,
    notes text,
    week_start date,
    user_id integer,
    day text,
    updated_at time with time zone,
    week_data jsonb,
    initiation date,
    project_id integer,
    resources integer[],
    subdepartment_id integer,
    department_id integer,
    CONSTRAINT dsu_friday_shape CHECK (((jsonb_typeof((week_data -> 'friday'::text)) = 'object'::text) AND ((week_data -> 'friday'::text) ?& ARRAY['todayUpdate'::text, 'nextSteps'::text, 'notes'::text]) AND (((((week_data -> 'friday'::text) - 'todayUpdate'::text) - 'nextSteps'::text) - 'notes'::text) = '{}'::jsonb))),
    CONSTRAINT dsu_monday_shape CHECK (((jsonb_typeof((week_data -> 'monday'::text)) = 'object'::text) AND ((week_data -> 'monday'::text) ?& ARRAY['todayUpdate'::text, 'nextSteps'::text, 'notes'::text]) AND (((((week_data -> 'monday'::text) - 'todayUpdate'::text) - 'nextSteps'::text) - 'notes'::text) = '{}'::jsonb))),
    CONSTRAINT dsu_thursday_shape CHECK (((jsonb_typeof((week_data -> 'thursday'::text)) = 'object'::text) AND ((week_data -> 'thursday'::text) ?& ARRAY['todayUpdate'::text, 'nextSteps'::text, 'notes'::text]) AND (((((week_data -> 'thursday'::text) - 'todayUpdate'::text) - 'nextSteps'::text) - 'notes'::text) = '{}'::jsonb))),
    CONSTRAINT dsu_tuesday_shape CHECK (((jsonb_typeof((week_data -> 'tuesday'::text)) = 'object'::text) AND ((week_data -> 'tuesday'::text) ?& ARRAY['todayUpdate'::text, 'nextSteps'::text, 'notes'::text]) AND (((((week_data -> 'tuesday'::text) - 'todayUpdate'::text) - 'nextSteps'::text) - 'notes'::text) = '{}'::jsonb))),
    CONSTRAINT dsu_wednesday_shape CHECK (((jsonb_typeof((week_data -> 'wednesday'::text)) = 'object'::text) AND ((week_data -> 'wednesday'::text) ?& ARRAY['todayUpdate'::text, 'nextSteps'::text, 'notes'::text]) AND (((((week_data -> 'wednesday'::text) - 'todayUpdate'::text) - 'nextSteps'::text) - 'notes'::text) = '{}'::jsonb))),
    CONSTRAINT dsu_week_is_object CHECK ((jsonb_typeof(week_data) = 'object'::text)),
    CONSTRAINT dsu_week_only_weekdays CHECK ((((((((week_data - 'monday'::text) - 'tuesday'::text) - 'wednesday'::text) - 'thursday'::text) - 'friday'::text) = '{}'::jsonb) AND (week_data ?& ARRAY['monday'::text, 'tuesday'::text, 'wednesday'::text, 'thursday'::text, 'friday'::text])))
);


--
-- Name: daily_sheet_update_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.daily_sheet_update_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_sheet_update_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.daily_sheet_update_id_seq OWNED BY schema_3.daily_sheet_update.id;


--
-- Name: daily_update_log; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.daily_update_log (
    id integer NOT NULL,
    week_start date NOT NULL,
    week_data jsonb NOT NULL,
    daily_update_id integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: daily_update_log_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.daily_update_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_update_log_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.daily_update_log_id_seq OWNED BY schema_3.daily_update_log.id;


--
-- Name: email_queue; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.email_queue (
    id integer NOT NULL,
    campaign_id integer,
    job_type character varying(50),
    payload jsonb,
    status character varying(20) DEFAULT 'pending'::character varying,
    attempts integer DEFAULT 0,
    run_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone
);


--
-- Name: email_queue_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.email_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.email_queue_id_seq OWNED BY schema_3.email_queue.id;


--
-- Name: employee; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee (
    employee_id integer,
    user_id integer,
    email_id character varying(100),
    date_of_joining date,
    job_title character varying(100),
    department character varying(100),
    office_location character varying(100),
    manager character varying(100),
    employment_type character varying(100),
    date_of_last_promotion date
);


--
-- Name: employee_timesheet; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_timesheet (
    id integer NOT NULL,
    employee_id integer,
    task_id integer,
    date date,
    timesheet time without time zone[]
);


--
-- Name: employee_timesheet_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_timesheet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_timesheet_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.employee_timesheet_id_seq OWNED BY schema_3.employee_timesheet.id;


--
-- Name: invoice_ap; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.invoice_ap (
    invoice_id integer NOT NULL,
    invoice_date date,
    due_date date,
    payment_status character varying(25),
    project_id integer,
    invoice_from integer,
    upload_invoice text,
    invoice_amount double precision,
    invoice_po text,
    invoiced_tasks json,
    ttm_id character varying(255),
    subconsultant_id integer
);


--
-- Name: invoice_ap_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.invoice_ap_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoice_ap_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.invoice_ap_id_seq OWNED BY schema_3.invoice_ap.invoice_id;


--
-- Name: invoices; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.invoices (
    invoice_id integer NOT NULL,
    project_id integer NOT NULL,
    bill_to integer,
    ship_to integer,
    payment_status character varying(20),
    invoice_status character varying(20),
    subtotal double precision,
    discount double precision,
    tax double precision,
    shipping double precision,
    rows jsonb[],
    invoice_code character varying(20),
    due_date date,
    date_created date,
    po_number text
);


--
-- Name: invoices_invoice_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.invoices_invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoices_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.invoices_invoice_id_seq OWNED BY schema_3.invoices.invoice_id;


--
-- Name: items; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.items (
    id integer NOT NULL,
    item_name text NOT NULL,
    unit text NOT NULL,
    unit_price numeric(12,2),
    quantity numeric
);


--
-- Name: items_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: items_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.items_id_seq OWNED BY schema_3.items.id;


--
-- Name: lesson_project_links; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.lesson_project_links (
    id integer NOT NULL,
    lesson_id integer NOT NULL,
    project_id integer NOT NULL,
    description text,
    linked_by_id integer,
    linked_by character varying(255),
    linked_at timestamp with time zone DEFAULT now()
);


--
-- Name: lesson_project_links_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.lesson_project_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lesson_project_links_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.lesson_project_links_id_seq OWNED BY schema_3.lesson_project_links.id;


--
-- Name: lessons_learned; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.lessons_learned (
    id integer NOT NULL,
    project_id integer NOT NULL,
    title character varying(255),
    description text,
    categories text[] DEFAULT '{}'::text[],
    root_cause text,
    recommendation text,
    project_phase character varying(50),
    impact_level character varying(20),
    project_type_tags text[] DEFAULT '{}'::text[],
    linked_task_ids integer[] DEFAULT '{}'::integer[],
    attachments text[] DEFAULT '{}'::text[],
    owner_id integer,
    created_by_id integer,
    created_by character varying(255),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    schedule_delays numeric,
    cost_impact numeric(14,2),
    status character varying(20) DEFAULT 'published'::character varying NOT NULL,
    department_ids integer[],
    subdepartment_ids integer[]
);


--
-- Name: lessons_learned_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.lessons_learned_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lessons_learned_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.lessons_learned_id_seq OWNED BY schema_3.lessons_learned.id;


--
-- Name: logs; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.logs (
    id integer NOT NULL,
    level text NOT NULL,
    message text NOT NULL,
    meta jsonb,
    "timestamp" timestamp with time zone DEFAULT now()
);


--
-- Name: logs_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: logs_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.logs_id_seq OWNED BY schema_3.logs.id;


--
-- Name: mam_transportation_inspections; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.mam_transportation_inspections (
    id integer NOT NULL,
    asset_db_id integer NOT NULL,
    asset_id character varying(30) NOT NULL,
    inspection_type character varying(10) NOT NULL,
    inspector_name character varying(200) NOT NULL,
    inspector_user_id integer,
    inspection_date date NOT NULL,
    status character varying(30) DEFAULT 'Draft'::character varying NOT NULL,
    signed_off_by character varying(200),
    signed_off_user_id integer,
    signed_off_at timestamp with time zone,
    sign_off_notes text,
    from_address text,
    from_lat numeric(10,7),
    from_lng numeric(10,7),
    to_address text,
    to_lat numeric(10,7),
    to_lng numeric(10,7),
    road_classification character varying(100),
    paser_rating smallint,
    surface_distress_entries jsonb DEFAULT '[]'::jsonb NOT NULL,
    recommended_treatment character varying(200),
    estimated_cost numeric(15,2),
    inspection_level character varying(100),
    structure_type character varying(100),
    from_station text,
    to_station text,
    bridge_length_m numeric(8,2),
    osim_road_classification character varying(100),
    osim_component_ratings jsonb DEFAULT '[]'::jsonb NOT NULL,
    bci_score numeric(5,2),
    is_load_posted boolean DEFAULT false,
    recommended_action character varying(200),
    inspector_notes text,
    photos text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mam_transportation_inspections_inspection_type_check CHECK (((inspection_type)::text = ANY ((ARRAY['PASER'::character varying, 'OSIM'::character varying])::text[]))),
    CONSTRAINT mam_transportation_inspections_paser_rating_check CHECK (((paser_rating IS NULL) OR ((paser_rating >= 1) AND (paser_rating <= 10)))),
    CONSTRAINT mam_transportation_inspections_status_check CHECK (((status)::text = ANY ((ARRAY['Draft'::character varying, 'Submitted'::character varying, 'Signed Off'::character varying, 'Rejected'::character varying])::text[])))
);


--
-- Name: mam_transportation_inspections_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.mam_transportation_inspections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mam_transportation_inspections_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.mam_transportation_inspections_id_seq OWNED BY schema_3.mam_transportation_inspections.id;


--
-- Name: notifications; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.notifications (
    id integer NOT NULL,
    employee_id character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    body text NOT NULL,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.notifications_id_seq OWNED BY schema_3.notifications.id;


--
-- Name: organization; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.organization (
    company_id integer NOT NULL,
    company_name character varying(255) NOT NULL,
    label character varying(255),
    address text,
    city_id integer,
    business_phone character varying(255),
    fax character varying(255),
    email text,
    website text,
    notes text,
    contact_type text,
    cv text,
    category text,
    status public.organizationstatus DEFAULT 'active'::public.organizationstatus,
    events jsonb DEFAULT '{"Open": [], "Click": [], "Bounce": [], "Delivery": [], "Complaint": [], "Subscription": []}'::jsonb,
    company_type text,
    company_type_id integer,
    department integer,
    unsubscribed boolean DEFAULT false,
    unsubscribed_at timestamp without time zone,
    email_invalid boolean DEFAULT false,
    email_invalid_reason text,
    email_invalid_at timestamp without time zone,
    region_id integer
);


--
-- Name: organization_company_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.organization_company_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_company_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.organization_company_id_seq OWNED BY schema_3.organization.company_id;


--
-- Name: organizationtype; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.organizationtype (
    cmpt_id integer,
    cmpt_name text,
    cmpt_desc text,
    cmpt_count integer
);


--
-- Name: people; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people (
    company_id integer,
    name text,
    company_type text,
    contact_type text,
    email text,
    job_title text,
    phone character varying(255),
    cv text,
    remarks text,
    alternate_phone text,
    address text,
    city_id integer,
    status text DEFAULT 'active'::text,
    events jsonb DEFAULT '{"Open": [], "Click": [], "Bounce": [], "Delivery": [], "Complaint": [], "Subscription": []}'::jsonb,
    label text,
    company_type_id integer,
    likes text,
    birthday character varying(20),
    anniversary character varying(20),
    id integer NOT NULL,
    project_ids integer[],
    unsubscribed boolean DEFAULT false,
    unsubscribed_at timestamp without time zone,
    email_status character varying(20) DEFAULT 'active'::character varying,
    is_hard_bounced boolean DEFAULT false,
    hard_bounce_at timestamp without time zone,
    email_invalid boolean DEFAULT false,
    email_invalid_reason text,
    email_invalid_at timestamp without time zone,
    phone_ext character varying(20),
    region_id integer,
    show_in_ttm boolean DEFAULT false NOT NULL
);


--
-- Name: people_activities; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people_activities (
    activity_id integer NOT NULL,
    people_id integer NOT NULL,
    company_id integer,
    project_id integer,
    activity_mode character varying(50) NOT NULL,
    summary text,
    detailed_notes text,
    activity_date timestamp without time zone,
    duration_minutes integer,
    follow_up_date timestamp without time zone,
    outcome character varying(100),
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: people_activities_activity_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.people_activities_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: people_activities_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.people_activities_activity_id_seq OWNED BY schema_3.people_activities.activity_id;


--
-- Name: people_conversation; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people_conversation (
    conversation_id integer NOT NULL,
    people_id integer,
    general jsonb[]
);


--
-- Name: people_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.people_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: people_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.people_id_seq OWNED BY schema_3.people.id;


--
-- Name: people_notes; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people_notes (
    note_id integer NOT NULL,
    people_id integer NOT NULL,
    note text NOT NULL,
    is_pinned boolean DEFAULT false,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: people_notes_note_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.people_notes_note_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: people_notes_note_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.people_notes_note_id_seq OWNED BY schema_3.people_notes.note_id;


--
-- Name: people_project_conversation; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people_project_conversation (
    conversation_id integer NOT NULL,
    people_id integer,
    project_id integer,
    chat jsonb[]
);


--
-- Name: people_reminders; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.people_reminders (
    reminder_id integer NOT NULL,
    people_id integer NOT NULL,
    reminder_date date NOT NULL,
    reminder_time time without time zone,
    details text,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: people_reminders_reminder_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.people_reminders_reminder_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: people_reminders_reminder_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.people_reminders_reminder_id_seq OWNED BY schema_3.people_reminders.reminder_id;


--
-- Name: pmis_module_access; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.pmis_module_access (
    id integer NOT NULL,
    user_id integer NOT NULL,
    access_granted boolean DEFAULT true,
    access_level character varying(50) DEFAULT 'full'::character varying,
    granted_by integer,
    granted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    grant_reason text,
    revoked boolean DEFAULT false,
    revoked_by integer,
    revoked_at timestamp without time zone,
    revoke_reason text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(100),
    updated_by character varying(100),
    CONSTRAINT chk_access_level CHECK (((access_level)::text = ANY ((ARRAY['full'::character varying, 'read_only'::character varying, 'restricted'::character varying])::text[])))
);


--
-- Name: TABLE pmis_module_access; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON TABLE schema_3.pmis_module_access IS 'Access control for PMIS module - whitelist of authorized users';


--
-- Name: COLUMN pmis_module_access.user_id; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.pmis_module_access.user_id IS 'Foreign key to users table';


--
-- Name: COLUMN pmis_module_access.access_level; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.pmis_module_access.access_level IS 'Level of access: full, read_only, or restricted';


--
-- Name: COLUMN pmis_module_access.revoked; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.pmis_module_access.revoked IS 'If true, access has been revoked even though record exists';


--
-- Name: pmis_module_access_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.pmis_module_access_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pmis_module_access_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.pmis_module_access_id_seq OWNED BY schema_3.pmis_module_access.id;


--
-- Name: po_approval_tokens; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.po_approval_tokens (
    token_id integer NOT NULL,
    po_id integer,
    token character varying(255) NOT NULL,
    approval_level integer NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    used boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: po_approval_tokens_token_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.po_approval_tokens_token_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: po_approval_tokens_token_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.po_approval_tokens_token_id_seq OWNED BY schema_3.po_approval_tokens.token_id;


--
-- Name: privileges; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.privileges (
    user_id integer NOT NULL,
    privilege_id character varying(50) NOT NULL
);


--
-- Name: processed_events; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.processed_events (
    event_id integer DEFAULT nextval('schema_118.processed_events_event_id_seq'::regclass) NOT NULL,
    event_type text NOT NULL,
    email text NOT NULL,
    campaign_id text NOT NULL,
    processed_at timestamp without time zone DEFAULT now()
);


--
-- Name: project_tags; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.project_tags (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: project_tags_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.project_tags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.project_tags_id_seq OWNED BY schema_3.project_tags.id;


--
-- Name: project_tasklists_map; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.project_tasklists_map (
    id integer NOT NULL,
    project_id integer NOT NULL,
    department_id integer NOT NULL,
    department_name text NOT NULL,
    template_id integer,
    mongo_doc_id character varying(24) NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    leads integer[] DEFAULT ARRAY[]::integer[],
    overall_progress integer DEFAULT 0,
    subdepartment_id integer,
    subdepartment_name text
);


--
-- Name: project_tasklists_map_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.project_tasklists_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_tasklists_map_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.project_tasklists_map_id_seq OWNED BY schema_3.project_tasklists_map.id;


--
-- Name: projects; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.projects (
    project_id integer NOT NULL,
    project_name text,
    date_created date,
    due_date date,
    description text,
    follow_up_date date,
    project_value integer,
    city_id integer,
    department_id integer,
    project_manager_id integer,
    status character varying(45),
    project_category_id integer,
    project_code character varying(45),
    folder_id character varying(255),
    team_member_ids integer[],
    extra_info json,
    project_type character varying(100),
    tasklist json[],
    ttm_id text,
    client_id integer,
    project_link text,
    site_id text,
    team_member text,
    department_name text,
    project_manager text,
    project_category text,
    subdepartment_id integer,
    quotation_yorkwest boolean,
    quotation2_decaste boolean,
    request_sent_to text,
    people_ids integer[],
    priority text,
    multiple_departments_id integer[],
    cad_standard_folder text,
    cad_standard_folder_id text,
    po_number text,
    multiple_subdepartments_id integer[],
    multiple_site_id text[],
    multiple_project_link text[],
    is_deleted boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by integer
);


--
-- Name: projects_project_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.projects_project_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_project_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.projects_project_id_seq OWNED BY schema_3.projects.project_id;


--
-- Name: proposal_clients; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_clients (
    id integer NOT NULL,
    client_company_name text NOT NULL,
    contact_person_name text,
    contact_person_designation text,
    organization_name text,
    phone text,
    email text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    logo_s3_key text
);


--
-- Name: proposal_clients_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_clients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_clients_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_clients_id_seq OWNED BY schema_3.proposal_clients.id;


--
-- Name: proposal_company; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_company (
    id integer NOT NULL,
    name text NOT NULL,
    profile text,
    logo_s3_key text
);


--
-- Name: proposal_company_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_company_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_company_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_company_id_seq OWNED BY schema_3.proposal_company.id;


--
-- Name: proposal_company_profile; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_company_profile (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    certifications_placeholder text,
    certifications_list jsonb,
    services text[],
    company_id integer,
    client_ids integer[]
);


--
-- Name: proposal_company_projects; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_company_projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id integer,
    department_id integer,
    subdepartment_id integer,
    project_cat_id integer,
    name text NOT NULL,
    project_from_year integer,
    project_to_year integer,
    proposal_value integer,
    client_name text,
    company_client_details text,
    phone_country_code text,
    phone_number text,
    email text,
    description text,
    team_members text[]
);


--
-- Name: proposal_generated_document; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_generated_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    url text,
    proposal_type schema_3.proposal_type DEFAULT 'RFP (Proposals)'::schema_3.proposal_type NOT NULL,
    proposal_id integer,
    proposal_name text NOT NULL,
    city text,
    city_id integer,
    client text,
    client_id text,
    department integer[] NOT NULL,
    sub_department integer[] NOT NULL,
    project_cat integer[] NOT NULL,
    company_name text,
    certifications_placeholder text,
    certifications_list json,
    profile text,
    clients text[],
    services text[],
    projects json,
    team_experience json,
    sub_consultant json,
    team_detail json,
    plans json,
    policies json,
    proposal_number text
);


--
-- Name: proposal_generator_master; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_generator_master (
    proposal_id integer NOT NULL,
    proposal_type character varying(255) NOT NULL,
    city_id integer,
    proposal_name character varying(500) NOT NULL,
    client_id integer,
    department_ids integer[],
    step_1_id integer,
    step_2_id integer,
    step_3_id integer,
    step_4_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_by integer,
    is_active boolean DEFAULT true,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    sub_department_ids integer[],
    project_category_id integer[],
    document_id character varying(50),
    document_path text
);


--
-- Name: proposal_generator_master_proposal_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_generator_master_proposal_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_generator_master_proposal_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_generator_master_proposal_id_seq OWNED BY schema_3.proposal_generator_master.proposal_id;


--
-- Name: proposal_plan; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_plan (
    id integer NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    plan_points json
);


--
-- Name: proposal_plan_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_plan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_plan_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_plan_id_seq OWNED BY schema_3.proposal_plan.id;


--
-- Name: proposal_plans; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_plans (
    id integer NOT NULL,
    plan_name text NOT NULL,
    plan_description text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: proposal_plans_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_plans_id_seq OWNED BY schema_3.proposal_plans.id;


--
-- Name: proposal_policies; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_policies (
    id integer NOT NULL,
    policy_name text NOT NULL,
    policy_description text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: proposal_policies_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_policies_id_seq OWNED BY schema_3.proposal_policies.id;


--
-- Name: proposal_project_experience; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_project_experience (
    id integer NOT NULL,
    collaboration_title text,
    collaboration_company_ids integer[] NOT NULL,
    project_title text NOT NULL,
    project_year text,
    project_value text,
    client_id integer,
    executed_by_company_ids integer[],
    team_member_ids integer[],
    project_description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    department_ids integer[],
    project_category_ids integer[],
    subdepartment_ids integer[] DEFAULT '{}'::integer[]
);


--
-- Name: proposal_project_experience_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_project_experience_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_project_experience_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_project_experience_id_seq OWNED BY schema_3.proposal_project_experience.id;


--
-- Name: proposal_step_1; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_step_1 (
    id integer NOT NULL,
    proposal_id integer NOT NULL,
    selected_company_ids integer[] NOT NULL,
    final_certifications jsonb NOT NULL,
    final_services text[] NOT NULL,
    final_clients text[] NOT NULL,
    breakdown jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    template_id integer
);


--
-- Name: proposal_step_1_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_step_1_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_step_1_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_step_1_id_seq OWNED BY schema_3.proposal_step_1.id;


--
-- Name: proposal_step_2; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_step_2 (
    id integer NOT NULL,
    proposal_id integer NOT NULL,
    selected_project_ids integer[] NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: proposal_step_2_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_step_2_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_step_2_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_step_2_id_seq OWNED BY schema_3.proposal_step_2.id;


--
-- Name: proposal_step_3; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_step_3 (
    id integer NOT NULL,
    proposal_id integer NOT NULL,
    selected_team_member_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    selected_subconsultant_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    selected_team_detail_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    subconsultant_variables json DEFAULT '{}'::json,
    team_designation_map jsonb DEFAULT '{}'::jsonb
);


--
-- Name: proposal_step_3_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_step_3_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_step_3_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_step_3_id_seq OWNED BY schema_3.proposal_step_3.id;


--
-- Name: proposal_step_4; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_step_4 (
    id integer NOT NULL,
    proposal_id integer NOT NULL,
    selected_plan_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    selected_policy_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: proposal_step_4_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_step_4_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_step_4_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_step_4_id_seq OWNED BY schema_3.proposal_step_4.id;


--
-- Name: proposal_sub_consultant; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_sub_consultant (
    id integer NOT NULL,
    name text NOT NULL,
    description_template text,
    template_variables json
);


--
-- Name: proposal_sub_consultant_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_sub_consultant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_sub_consultant_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_sub_consultant_id_seq OWNED BY schema_3.proposal_sub_consultant.id;


--
-- Name: proposal_team_detail; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_team_detail (
    id integer NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    team_members json
);


--
-- Name: proposal_team_detail_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_team_detail_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_team_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_team_detail_id_seq OWNED BY schema_3.proposal_team_detail.id;


--
-- Name: proposal_team_member; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_team_member (
    id integer NOT NULL,
    name text NOT NULL,
    designation integer NOT NULL,
    years_of_exp integer NOT NULL,
    company_id integer NOT NULL,
    qualifications text NOT NULL,
    description text NOT NULL,
    prof_affiliation text NOT NULL,
    rel_exp json
);


--
-- Name: proposal_team_member_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_team_member_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_team_member_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_team_member_id_seq OWNED BY schema_3.proposal_team_member.id;


--
-- Name: proposal_team_member_overrides; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_team_member_overrides (
    id integer NOT NULL,
    proposal_id integer NOT NULL,
    team_member_id integer NOT NULL,
    name_override text,
    designation_override text,
    years_of_exp_override integer,
    qualifications_override text,
    rel_exp_override jsonb,
    description_override text,
    rendered_json jsonb,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: proposal_team_member_overrides_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_team_member_overrides_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_team_member_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_team_member_overrides_id_seq OWNED BY schema_3.proposal_team_member_overrides.id;


--
-- Name: proposal_team_members; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_team_members (
    id integer NOT NULL,
    member_name text NOT NULL,
    designation text,
    company_id integer,
    phone text,
    email text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: proposal_team_members_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_team_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_team_members_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_team_members_id_seq OWNED BY schema_3.proposal_team_members.id;


--
-- Name: proposal_template_master; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposal_template_master (
    id integer NOT NULL,
    company_ids integer[] NOT NULL,
    template_type character varying(100) DEFAULT 'intro'::character varying NOT NULL,
    template_text text NOT NULL,
    title text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: proposal_template_master_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposal_template_master_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposal_template_master_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposal_template_master_id_seq OWNED BY schema_3.proposal_template_master.id;


--
-- Name: proposals; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.proposals (
    proposal_id integer NOT NULL,
    city_id integer,
    department_id integer,
    project_name character varying(255),
    question_deadline date,
    closing_deadline date,
    project_manager_id integer,
    design_price double precision DEFAULT 0,
    provisional_items double precision DEFAULT 0,
    contract_admin_price double precision DEFAULT 0,
    sub_consultant_price double precision DEFAULT 0,
    winning_price double precision DEFAULT 0,
    winning_bidder text,
    project_cat_id integer,
    created_at date,
    status character varying(45),
    debriefing character varying(45),
    folder_id character varying(255),
    team integer[],
    bookmark integer[],
    priority text DEFAULT 'Medium'::text,
    proposal_generator_link text,
    rating integer,
    plantakers_list text[],
    bidders_list text[],
    client_contact_details text,
    client_id integer,
    debriefing_notes text,
    total_bid_price double precision,
    team_members json[],
    source text,
    partners integer[],
    proposal_link text,
    site_id text,
    result character varying(45),
    subdepartment_id integer,
    source_id integer,
    parent_id integer,
    region_id integer,
    action character varying(50),
    contact_name character varying(255),
    contact_phone_no character varying(15),
    email character varying(255),
    address text,
    comments text,
    ttm_id text
);


--
-- Name: proposals_proposal_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.proposals_proposal_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposals_proposal_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.proposals_proposal_id_seq OWNED BY schema_3.proposals.proposal_id;


--
-- Name: purchase_orders; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.purchase_orders (
    po_id integer NOT NULL,
    po_number character varying(100) NOT NULL,
    po_code character varying(50) NOT NULL,
    project_id integer,
    company_id integer,
    requested_by integer,
    approved_by integer,
    status character varying(50) DEFAULT 'draft'::character varying,
    subtotal numeric(10,2) DEFAULT 0 NOT NULL,
    tax numeric(10,2) DEFAULT 0,
    discount numeric(5,2) DEFAULT 0,
    shipping numeric(10,2) DEFAULT 0,
    total_amount numeric(10,2) DEFAULT 0 NOT NULL,
    delivery_date date,
    terms_conditions text,
    notes text,
    rows jsonb,
    date_created timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    date_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_by integer,
    ttm_id text,
    vendor_reference_number character varying(255),
    assignment_description text,
    terms_conditions_ids integer[] DEFAULT '{}'::integer[],
    approval_level integer DEFAULT 0,
    approval_status character varying(50) DEFAULT 'pending'::character varying,
    level_1_approver_id integer,
    level_1_approved_at timestamp without time zone,
    level_1_approved_by integer,
    level_2_approver_id integer,
    level_2_approved_at timestamp without time zone,
    level_2_approved_by integer,
    rejection_reason text,
    rejected_at timestamp without time zone,
    rejected_by integer,
    subconsultant_id integer
);


--
-- Name: purchase_orders_po_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.purchase_orders_po_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchase_orders_po_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.purchase_orders_po_id_seq OWNED BY schema_3.purchase_orders.po_id;


--
-- Name: region_comments; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.region_comments (
    serial_number integer NOT NULL,
    region_name character varying(255) NOT NULL,
    comments jsonb[]
);


--
-- Name: region_comments_serial_number_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.region_comments_serial_number_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_comments_serial_number_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.region_comments_serial_number_seq OWNED BY schema_3.region_comments.serial_number;


--
-- Name: rfps; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.rfps (
    rfp_id integer NOT NULL,
    department_id integer,
    action character varying(255),
    project_manager_id integer,
    city_id integer,
    start_date date,
    submission_date date,
    project_name text,
    rfp_number character varying(255),
    source character varying(255),
    project_cat_id integer,
    created_at date,
    folder_id character varying(255),
    remarks text,
    rating integer,
    organization_ids integer[],
    rfp_link text,
    site_id text,
    client_id integer,
    subdepartment_id integer,
    rfp_url text,
    site_visit_mandatory boolean,
    meeting_date date,
    meeting_time time without time zone,
    meeting_location text,
    meeting_link text,
    meeting_description text,
    source_id integer,
    client text
);


--
-- Name: rfps_rfp_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.rfps_rfp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rfps_rfp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.rfps_rfp_id_seq OWNED BY schema_3.rfps.rfp_id;


--
-- Name: section; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.section (
    id integer NOT NULL,
    name text NOT NULL
);


--
-- Name: section_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.section_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: section_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.section_id_seq OWNED BY schema_3.section.id;


--
-- Name: ses_access_management; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ses_access_management (
    user_id integer,
    email text,
    date date,
    action text,
    permission_level text,
    site_id text,
    site_name text,
    status boolean,
    business_justification text,
    owner_user_id integer,
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ses_access_management_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.ses_access_management_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ses_access_management_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.ses_access_management_id_seq OWNED BY schema_3.ses_access_management.id;


--
-- Name: ses_mapping; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ses_mapping (
)
INHERITS (schema_118.ses_mapping);


--
-- Name: ses_request; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ses_request (
    id integer,
    site_id integer,
    site_name text,
    business_justification text,
    approved boolean
);


--
-- Name: sescampaigntable; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.sescampaigntable (
    cmpid integer NOT NULL,
    cmpname character varying(255) NOT NULL,
    status public.campaignstatus DEFAULT 'created'::public.campaignstatus NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    scheduledat timestamp without time zone,
    recipient json NOT NULL,
    cmp_count jsonb DEFAULT '{"Open": 0, "Click": 0, "Bounce": 0, "Delivery": 0, "Complaint": 0, "Subscription": 0}'::jsonb,
    senderemail character varying(255) NOT NULL,
    sendername character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    tag character varying(255),
    params json,
    templateid integer,
    textcontent text,
    htmlcontent text,
    attachments jsonb,
    recipientcount integer,
    ab_testing_enabled boolean DEFAULT false,
    ab_test_sample_percentage integer DEFAULT 20,
    ab_test_duration_minutes integer DEFAULT 60,
    ab_test_status character varying(20) DEFAULT NULL::character varying,
    ab_test_started_at timestamp without time zone,
    ab_test_completed_at timestamp without time zone,
    winner_criteria character varying(20) DEFAULT 'open_rate'::character varying,
    contactparams jsonb,
    winner_variant_id integer
);


--
-- Name: sescampaigntable_cmpid_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.sescampaigntable_cmpid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sescampaigntable_cmpid_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.sescampaigntable_cmpid_seq OWNED BY schema_3.sescampaigntable.cmpid;


--
-- Name: sestemplatetable; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.sestemplatetable (
    tmpid integer DEFAULT nextval('schema_118.sestemplatetable_tmpid_seq'::regclass) NOT NULL,
    tmpname character varying(255) NOT NULL,
    subject character varying(255),
    htmlcontents3url text NOT NULL,
    params character varying[],
    contactparams character varying[],
    status public.templatestatus DEFAULT 'inactive'::public.templatestatus NOT NULL,
    thumbnailimageurl text
);


--
-- Name: shared_folder; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.shared_folder (
    id integer NOT NULL,
    subdepartment_id integer,
    subdepartment_name text,
    folder jsonb,
    subdepartment_site_id character varying
);


--
-- Name: shared_folder_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.shared_folder_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shared_folder_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.shared_folder_id_seq OWNED BY schema_3.shared_folder.id;


--
-- Name: sharepoint_folder_structures; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.sharepoint_folder_structures (
    id integer NOT NULL,
    structure_name character varying(255),
    structure_data jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: sharepoint_folder_structures_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.sharepoint_folder_structures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sharepoint_folder_structures_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.sharepoint_folder_structures_id_seq OWNED BY schema_3.sharepoint_folder_structures.id;


--
-- Name: sharepoint_missing_folder; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.sharepoint_missing_folder (
    id integer,
    name text,
    city text,
    "ID" text,
    date date,
    type text,
    created_at timestamp with time zone
);


--
-- Name: specification; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.specification (
    id integer NOT NULL,
    spec_no text,
    opss text,
    section_id integer,
    description text,
    format character varying(10) DEFAULT 'html'::character varying NOT NULL,
    CONSTRAINT specification_format_check CHECK (((format)::text = ANY (ARRAY[('html'::character varying)::text, ('markdown'::character varying)::text])))
);


--
-- Name: specification_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.specification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: specification_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.specification_id_seq OWNED BY schema_3.specification.id;


--
-- Name: specification_items; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.specification_items (
    spec_id integer NOT NULL,
    item_id integer NOT NULL
);


--
-- Name: subconsultants; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.subconsultants (
    id integer NOT NULL,
    project_id integer NOT NULL,
    ttm_document_id character varying(24) NOT NULL,
    company_id integer NOT NULL,
    task_name character varying(255) NOT NULL,
    proposal_number character varying(100),
    proposal_date date,
    total_price numeric(15,2),
    comments text,
    subtasks jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    invoiced_amounts jsonb DEFAULT '[]'::jsonb,
    carry_on_amounts jsonb DEFAULT '[]'::jsonb
);


--
-- Name: subconsultants_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.subconsultants_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subconsultants_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.subconsultants_id_seq OWNED BY schema_3.subconsultants.id;


--
-- Name: tasklist_templates; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tasklist_templates (
    template_id integer NOT NULL,
    department_id integer NOT NULL,
    department_name text NOT NULL,
    template_name text NOT NULL,
    template_data jsonb NOT NULL,
    version integer DEFAULT 1,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    subdepartment_id integer,
    subdepartment_name text
);


--
-- Name: tasklist_templates_template_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tasklist_templates_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasklist_templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tasklist_templates_template_id_seq OWNED BY schema_3.tasklist_templates.template_id;


--
-- Name: tasks; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tasks (
    task_id integer NOT NULL,
    type character varying(45),
    title character varying(245),
    description text,
    start_date date,
    due_date date,
    completed_date date,
    attachments text,
    assigned_by integer,
    reviewed_by integer,
    assigned_to integer,
    priority text,
    status text,
    id integer,
    progress integer DEFAULT 0,
    ttm_id text,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    outlook_event_id text,
    group_id character varying(255),
    project_id integer,
    remarks text,
    reminder character varying(20) DEFAULT NULL::character varying,
    reminder_sent_at timestamp with time zone,
    reminder_sent_by integer,
    dependent_on_type character varying(50) DEFAULT NULL::character varying,
    dependent_on_id integer,
    parent_id integer,
    kanban_order double precision DEFAULT 0,
    change_log jsonb DEFAULT '[]'::jsonb,
    comments jsonb DEFAULT '[]'::jsonb,
    is_requested boolean DEFAULT false,
    requested_by integer,
    requested_at timestamp with time zone,
    progress_is_manual boolean DEFAULT false,
    is_confidential boolean DEFAULT false,
    story_points integer,
    story_points_is_manual boolean DEFAULT false,
    started_on timestamp with time zone,
    CONSTRAINT tasks_reminder_check CHECK (((reminder)::text = ANY (ARRAY[('notify'::character varying)::text, ('follow_up'::character varying)::text])))
);


--
-- Name: tasks_task_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tasks_task_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_task_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tasks_task_id_seq OWNED BY schema_3.tasks.task_id;


--
-- Name: template; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.template (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    template text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    html_s3_url character varying,
    thumbnail_s3_url character varying
);


--
-- Name: template_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: template_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.template_id_seq OWNED BY schema_3.template.id;


--
-- Name: template_style_config; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.template_style_config (
    id integer NOT NULL,
    template_id integer NOT NULL,
    style_name character varying(50) NOT NULL,
    font_name character varying(100) DEFAULT 'Calibri'::character varying,
    font_size integer DEFAULT 12,
    font_color character varying(7) DEFAULT '#000000'::character varying,
    font_bg_color character varying(7),
    is_bold boolean DEFAULT false,
    is_italic boolean DEFAULT false,
    is_underline boolean DEFAULT false,
    alignment character varying(20) DEFAULT 'left'::character varying,
    line_spacing numeric(3,2),
    space_before integer DEFAULT 0,
    space_after integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: template_style_config_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.template_style_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: template_style_config_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.template_style_config_id_seq OWNED BY schema_3.template_style_config.id;


--
-- Name: tender; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tender (
    id integer NOT NULL,
    tender_name character varying(255),
    project_id integer,
    project_number character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(100),
    updated_by character varying(100),
    city character varying(100),
    mandatory_site_visit timestamp without time zone,
    deadline_for_question timestamp without time zone,
    closing_date timestamp without time zone,
    project_scope text,
    link text,
    selected_headers jsonb,
    section_dynamic_data jsonb
);


--
-- Name: tender_document_static_sections; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tender_document_static_sections (
    id integer NOT NULL,
    section_key character varying(100) NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    format character varying(10) DEFAULT 'markdown'::character varying NOT NULL,
    is_optional boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tender_document_static_sections_format_check CHECK (((format)::text = ANY (ARRAY[('markdown'::character varying)::text, ('html'::character varying)::text])))
);


--
-- Name: tender_document_static_sections_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tender_document_static_sections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tender_document_static_sections_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tender_document_static_sections_id_seq OWNED BY schema_3.tender_document_static_sections.id;


--
-- Name: tender_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tender_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tender_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tender_id_seq OWNED BY schema_3.tender.id;


--
-- Name: tender_item; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tender_item (
    id integer NOT NULL,
    tender_id integer,
    item_id integer,
    quantity numeric,
    unit_price numeric,
    total numeric,
    serial integer
);


--
-- Name: tender_item_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tender_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tender_item_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tender_item_id_seq OWNED BY schema_3.tender_item.id;


--
-- Name: terms_conditions; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.terms_conditions (
    tc_id integer NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    is_active boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: terms_conditions_tc_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.terms_conditions_tc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: terms_conditions_tc_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.terms_conditions_tc_id_seq OWNED BY schema_3.terms_conditions.tc_id;


--
-- Name: tf_ai_messages; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tf_ai_messages (
    id integer NOT NULL,
    session_id character varying(255),
    user_id character varying(255) NOT NULL,
    role character varying(50) NOT NULL,
    content jsonb NOT NULL,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: tf_ai_messages_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tf_ai_messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tf_ai_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tf_ai_messages_id_seq OWNED BY schema_3.tf_ai_messages.id;


--
-- Name: tf_ai_sessions; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tf_ai_sessions (
    session_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    title character varying(255),
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: timesheet; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.timesheet (
    id integer NOT NULL,
    week_data jsonb,
    task_id integer,
    task text,
    project_id integer,
    task_description text,
    week_start date,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    emp_id integer,
    status text,
    manager_comment text,
    submit_date date,
    manager_id integer,
    submitted_at timestamp with time zone,
    approved_at timestamp with time zone
);


--
-- Name: timesheet_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.timesheet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timesheet_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.timesheet_id_seq OWNED BY schema_3.timesheet.id;


--
-- Name: tracker; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.tracker (
    tracker_id integer NOT NULL,
    user_id integer NOT NULL,
    module text,
    datetime timestamp with time zone,
    os text
);


--
-- Name: tracker_tracker_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.tracker_tracker_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tracker_tracker_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.tracker_tracker_id_seq OWNED BY schema_3.tracker.tracker_id;


--
-- Name: transmittal_categories; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.transmittal_categories (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    created_by character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: transmittal_categories_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.transmittal_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transmittal_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.transmittal_categories_id_seq OWNED BY schema_3.transmittal_categories.id;


--
-- Name: transmittals; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.transmittals (
    id integer NOT NULL,
    project_id integer,
    transmittal_no character varying(100) NOT NULL,
    date date,
    file_url text NOT NULL,
    file_name text,
    category character varying(100) NOT NULL,
    reviewer_ids integer[] DEFAULT '{}'::integer[],
    created_by_id integer,
    created_by character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: transmittals_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.transmittals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transmittals_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.transmittals_id_seq OWNED BY schema_3.transmittals.id;


--
-- Name: ttm_departments; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ttm_departments (
    id integer NOT NULL,
    name text NOT NULL,
    source_department_id integer,
    is_custom boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: ttm_departments_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.ttm_departments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ttm_departments_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.ttm_departments_id_seq OWNED BY schema_3.ttm_departments.id;


--
-- Name: ttm_designations; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ttm_designations (
    id integer NOT NULL,
    name text NOT NULL,
    source_job_id integer,
    is_custom boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: ttm_designations_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.ttm_designations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ttm_designations_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.ttm_designations_id_seq OWNED BY schema_3.ttm_designations.id;


--
-- Name: ttm_table; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.ttm_table (
    ttm_id integer NOT NULL,
    data jsonb,
    manpower jsonb
);


--
-- Name: ttm_table_ttm_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.ttm_table_ttm_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ttm_table_ttm_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.ttm_table_ttm_id_seq OWNED BY schema_3.ttm_table.ttm_id;


--
-- Name: user_fcm_tokens; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.user_fcm_tokens (
    id integer NOT NULL,
    user_id integer NOT NULL,
    fcm_token text NOT NULL,
    device_type character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true
);


--
-- Name: user_fcm_tokens_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.user_fcm_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_fcm_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.user_fcm_tokens_id_seq OWNED BY schema_3.user_fcm_tokens.id;


--
-- Name: users; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.users (
    user_id integer NOT NULL,
    auth_id integer,
    role character varying(50),
    first_name character varying(100),
    last_name character varying(100),
    email character varying(255),
    joining_date date,
    phone character varying(20),
    status character varying(50),
    filename character varying(255),
    job_id integer,
    dept_id integer,
    direct_manager_id integer,
    office_location character varying(255),
    date_of_last_promotion date,
    employee_type character varying(255),
    employment_type character varying(255),
    dashboard_role integer,
    team integer[],
    managed_department_id integer[],
    managed_subdepartment_id bigint[],
    teams_user_id uuid
);


--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.users_user_id_seq OWNED BY schema_3.users.user_id;


--
-- Name: ab_email_events id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ab_email_events ALTER COLUMN id SET DEFAULT nextval('schema_3.ab_email_events_id_seq'::regclass);


--
-- Name: automation_emails id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_emails ALTER COLUMN id SET DEFAULT nextval('schema_3.automation_emails_id_seq'::regclass);


--
-- Name: automation_enrollments id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_enrollments ALTER COLUMN id SET DEFAULT nextval('schema_3.automation_enrollments_id_seq'::regclass);


--
-- Name: automation_flows id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_flows ALTER COLUMN id SET DEFAULT nextval('schema_3.automation_flows_id_seq'::regclass);


--
-- Name: automation_logs id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_logs ALTER COLUMN id SET DEFAULT nextval('schema_3.automation_logs_id_seq'::regclass);


--
-- Name: campaign id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_id_seq1'::regclass);


--
-- Name: campaign_audience id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_audience ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_audience_id_seq'::regclass);


--
-- Name: campaign_content_calendar id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_content_calendar ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_id_seq'::regclass);


--
-- Name: campaign_recipient id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_recipient ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_recipient_id_seq'::regclass);


--
-- Name: campaign_senders_email id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_senders_email ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_senders_email_id_seq'::regclass);


--
-- Name: campaign_variants id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_variants ALTER COLUMN id SET DEFAULT nextval('schema_3.campaign_variants_id_seq'::regclass);


--
-- Name: city_tender_templates id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.city_tender_templates ALTER COLUMN id SET DEFAULT nextval('schema_3.city_tender_templates_id_seq'::regclass);


--
-- Name: client_email_region_pms id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_region_pms ALTER COLUMN id SET DEFAULT nextval('schema_3.client_email_region_pms_id_seq'::regclass);


--
-- Name: client_email_regions region_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_regions ALTER COLUMN region_id SET DEFAULT nextval('schema_3.client_email_regions_region_id_seq'::regclass);


--
-- Name: client_email_templates id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_templates ALTER COLUMN id SET DEFAULT nextval('schema_3.client_email_templates_id_seq'::regclass);


--
-- Name: cokl_inspection_deficiencies id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_deficiencies ALTER COLUMN id SET DEFAULT nextval('schema_3.cokl_inspection_deficiencies_id_seq'::regclass);


--
-- Name: cokl_inspection_driveways id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_driveways ALTER COLUMN id SET DEFAULT nextval('schema_3.cokl_inspection_driveways_id_seq'::regclass);


--
-- Name: cokl_no_report_inspections id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_no_report_inspections ALTER COLUMN id SET DEFAULT nextval('schema_3.cokl_no_report_inspections_id_seq'::regclass);


--
-- Name: cokl_site_inspections id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_site_inspections ALTER COLUMN id SET DEFAULT nextval('schema_3.cokl_site_inspections_id_seq'::regclass);


--
-- Name: daily_sheet_update id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.daily_sheet_update ALTER COLUMN id SET DEFAULT nextval('schema_3.daily_sheet_update_id_seq'::regclass);


--
-- Name: daily_update_log id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.daily_update_log ALTER COLUMN id SET DEFAULT nextval('schema_3.daily_update_log_id_seq'::regclass);


--
-- Name: dashboard dashboard_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.dashboard ALTER COLUMN dashboard_id SET DEFAULT nextval('schema_3."Dashboard_dashboard_id_seq"'::regclass);


--
-- Name: email_queue id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.email_queue ALTER COLUMN id SET DEFAULT nextval('schema_3.email_queue_id_seq'::regclass);


--
-- Name: employee_timesheet id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_timesheet ALTER COLUMN id SET DEFAULT nextval('schema_3.employee_timesheet_id_seq'::regclass);


--
-- Name: invoice_ap invoice_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.invoice_ap ALTER COLUMN invoice_id SET DEFAULT nextval('schema_3.invoice_ap_id_seq'::regclass);


--
-- Name: invoices invoice_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.invoices ALTER COLUMN invoice_id SET DEFAULT nextval('schema_3.invoices_invoice_id_seq'::regclass);


--
-- Name: items id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.items ALTER COLUMN id SET DEFAULT nextval('schema_3.items_id_seq'::regclass);


--
-- Name: lesson_project_links id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lesson_project_links ALTER COLUMN id SET DEFAULT nextval('schema_3.lesson_project_links_id_seq'::regclass);


--
-- Name: lessons_learned id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lessons_learned ALTER COLUMN id SET DEFAULT nextval('schema_3.lessons_learned_id_seq'::regclass);


--
-- Name: logs id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.logs ALTER COLUMN id SET DEFAULT nextval('schema_3.logs_id_seq'::regclass);


--
-- Name: mam_transportation_inspections id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.mam_transportation_inspections ALTER COLUMN id SET DEFAULT nextval('schema_3.mam_transportation_inspections_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.notifications ALTER COLUMN id SET DEFAULT nextval('schema_3.notifications_id_seq'::regclass);


--
-- Name: organization company_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.organization ALTER COLUMN company_id SET DEFAULT nextval('schema_3.organization_company_id_seq'::regclass);


--
-- Name: people id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people ALTER COLUMN id SET DEFAULT nextval('schema_3.people_id_seq'::regclass);


--
-- Name: people_activities activity_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_activities ALTER COLUMN activity_id SET DEFAULT nextval('schema_3.people_activities_activity_id_seq'::regclass);


--
-- Name: people_notes note_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_notes ALTER COLUMN note_id SET DEFAULT nextval('schema_3.people_notes_note_id_seq'::regclass);


--
-- Name: people_reminders reminder_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_reminders ALTER COLUMN reminder_id SET DEFAULT nextval('schema_3.people_reminders_reminder_id_seq'::regclass);


--
-- Name: pmis_module_access id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.pmis_module_access ALTER COLUMN id SET DEFAULT nextval('schema_3.pmis_module_access_id_seq'::regclass);


--
-- Name: po_approval_tokens token_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.po_approval_tokens ALTER COLUMN token_id SET DEFAULT nextval('schema_3.po_approval_tokens_token_id_seq'::regclass);


--
-- Name: project_tags id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tags ALTER COLUMN id SET DEFAULT nextval('schema_3.project_tags_id_seq'::regclass);


--
-- Name: project_tasklists_map id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tasklists_map ALTER COLUMN id SET DEFAULT nextval('schema_3.project_tasklists_map_id_seq'::regclass);


--
-- Name: projects project_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.projects ALTER COLUMN project_id SET DEFAULT nextval('schema_3.projects_project_id_seq'::regclass);


--
-- Name: proposal_clients id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_clients ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_clients_id_seq'::regclass);


--
-- Name: proposal_company id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_company_id_seq'::regclass);


--
-- Name: proposal_generator_master proposal_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_generator_master ALTER COLUMN proposal_id SET DEFAULT nextval('schema_3.proposal_generator_master_proposal_id_seq'::regclass);


--
-- Name: proposal_plan id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_plan ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_plan_id_seq'::regclass);


--
-- Name: proposal_plans id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_plans ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_plans_id_seq'::regclass);


--
-- Name: proposal_policies id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_policies ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_policies_id_seq'::regclass);


--
-- Name: proposal_project_experience id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_project_experience ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_project_experience_id_seq'::regclass);


--
-- Name: proposal_step_1 id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_1 ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_step_1_id_seq'::regclass);


--
-- Name: proposal_step_2 id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_2 ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_step_2_id_seq'::regclass);


--
-- Name: proposal_step_3 id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_3 ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_step_3_id_seq'::regclass);


--
-- Name: proposal_step_4 id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_4 ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_step_4_id_seq'::regclass);


--
-- Name: proposal_sub_consultant id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_sub_consultant ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_sub_consultant_id_seq'::regclass);


--
-- Name: proposal_team_detail id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_detail ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_team_detail_id_seq'::regclass);


--
-- Name: proposal_team_member id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_team_member_id_seq'::regclass);


--
-- Name: proposal_team_member_overrides id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member_overrides ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_team_member_overrides_id_seq'::regclass);


--
-- Name: proposal_team_members id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_members ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_team_members_id_seq'::regclass);


--
-- Name: proposal_template_master id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_template_master ALTER COLUMN id SET DEFAULT nextval('schema_3.proposal_template_master_id_seq'::regclass);


--
-- Name: proposals proposal_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposals ALTER COLUMN proposal_id SET DEFAULT nextval('schema_3.proposals_proposal_id_seq'::regclass);


--
-- Name: purchase_orders po_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.purchase_orders ALTER COLUMN po_id SET DEFAULT nextval('schema_3.purchase_orders_po_id_seq'::regclass);


--
-- Name: region_comments serial_number; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.region_comments ALTER COLUMN serial_number SET DEFAULT nextval('schema_3.region_comments_serial_number_seq'::regclass);


--
-- Name: rfps rfp_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.rfps ALTER COLUMN rfp_id SET DEFAULT nextval('schema_3.rfps_rfp_id_seq'::regclass);


--
-- Name: section id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.section ALTER COLUMN id SET DEFAULT nextval('schema_3.section_id_seq'::regclass);


--
-- Name: ses_access_management id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ses_access_management ALTER COLUMN id SET DEFAULT nextval('schema_3.ses_access_management_id_seq'::regclass);


--
-- Name: ses_mapping created_at; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ses_mapping ALTER COLUMN created_at SET DEFAULT now();


--
-- Name: ses_mapping id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ses_mapping ALTER COLUMN id SET DEFAULT nextval('schema_118.ses_mapping_id_seq'::regclass);


--
-- Name: sescampaigntable cmpid; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sescampaigntable ALTER COLUMN cmpid SET DEFAULT nextval('schema_3.sescampaigntable_cmpid_seq'::regclass);


--
-- Name: shared_folder id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.shared_folder ALTER COLUMN id SET DEFAULT nextval('schema_3.shared_folder_id_seq'::regclass);


--
-- Name: sharepoint_folder_structures id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sharepoint_folder_structures ALTER COLUMN id SET DEFAULT nextval('schema_3.sharepoint_folder_structures_id_seq'::regclass);


--
-- Name: specification id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification ALTER COLUMN id SET DEFAULT nextval('schema_3.specification_id_seq'::regclass);


--
-- Name: subconsultants id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.subconsultants ALTER COLUMN id SET DEFAULT nextval('schema_3.subconsultants_id_seq'::regclass);


--
-- Name: tasklist_templates template_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasklist_templates ALTER COLUMN template_id SET DEFAULT nextval('schema_3.tasklist_templates_template_id_seq'::regclass);


--
-- Name: tasks task_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasks ALTER COLUMN task_id SET DEFAULT nextval('schema_3.tasks_task_id_seq'::regclass);


--
-- Name: template id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.template ALTER COLUMN id SET DEFAULT nextval('schema_3.template_id_seq'::regclass);


--
-- Name: template_style_config id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.template_style_config ALTER COLUMN id SET DEFAULT nextval('schema_3.template_style_config_id_seq'::regclass);


--
-- Name: tender id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender ALTER COLUMN id SET DEFAULT nextval('schema_3.tender_id_seq'::regclass);


--
-- Name: tender_document_static_sections id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_document_static_sections ALTER COLUMN id SET DEFAULT nextval('schema_3.tender_document_static_sections_id_seq'::regclass);


--
-- Name: tender_item id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_item ALTER COLUMN id SET DEFAULT nextval('schema_3.tender_item_id_seq'::regclass);


--
-- Name: terms_conditions tc_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.terms_conditions ALTER COLUMN tc_id SET DEFAULT nextval('schema_3.terms_conditions_tc_id_seq'::regclass);


--
-- Name: tf_ai_messages id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tf_ai_messages ALTER COLUMN id SET DEFAULT nextval('schema_3.tf_ai_messages_id_seq'::regclass);


--
-- Name: timesheet id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.timesheet ALTER COLUMN id SET DEFAULT nextval('schema_3.timesheet_id_seq'::regclass);


--
-- Name: tracker tracker_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tracker ALTER COLUMN tracker_id SET DEFAULT nextval('schema_3.tracker_tracker_id_seq'::regclass);


--
-- Name: transmittal_categories id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittal_categories ALTER COLUMN id SET DEFAULT nextval('schema_3.transmittal_categories_id_seq'::regclass);


--
-- Name: transmittals id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittals ALTER COLUMN id SET DEFAULT nextval('schema_3.transmittals_id_seq'::regclass);


--
-- Name: ttm ttm_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm ALTER COLUMN ttm_id SET DEFAULT nextval('schema_3."TTM_ttm_id_seq"'::regclass);


--
-- Name: ttm_departments id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_departments ALTER COLUMN id SET DEFAULT nextval('schema_3.ttm_departments_id_seq'::regclass);


--
-- Name: ttm_designations id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_designations ALTER COLUMN id SET DEFAULT nextval('schema_3.ttm_designations_id_seq'::regclass);


--
-- Name: ttm_table ttm_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_table ALTER COLUMN ttm_id SET DEFAULT nextval('schema_3.ttm_table_ttm_id_seq'::regclass);


--
-- Name: user_fcm_tokens id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.user_fcm_tokens ALTER COLUMN id SET DEFAULT nextval('schema_3.user_fcm_tokens_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users ALTER COLUMN user_id SET DEFAULT nextval('schema_3.users_user_id_seq'::regclass);


--
-- Name: ttm TTM_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm
    ADD CONSTRAINT "TTM_pkey" PRIMARY KEY (ttm_id);


--
-- Name: ab_email_events ab_email_events_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ab_email_events
    ADD CONSTRAINT ab_email_events_pkey PRIMARY KEY (id);


--
-- Name: automation_emails automation_emails_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_emails
    ADD CONSTRAINT automation_emails_pkey PRIMARY KEY (id);


--
-- Name: automation_enrollments automation_enrollments_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_enrollments
    ADD CONSTRAINT automation_enrollments_pkey PRIMARY KEY (id);


--
-- Name: automation_flows automation_flows_cmpid_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_flows
    ADD CONSTRAINT automation_flows_cmpid_key UNIQUE (cmpid);


--
-- Name: automation_flows automation_flows_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_flows
    ADD CONSTRAINT automation_flows_pkey PRIMARY KEY (id);


--
-- Name: automation_logs automation_logs_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_logs
    ADD CONSTRAINT automation_logs_pkey PRIMARY KEY (id);


--
-- Name: campaign_audience campaign_audience_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_audience
    ADD CONSTRAINT campaign_audience_pkey PRIMARY KEY (id);


--
-- Name: campaign_content_calendar campaign_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_content_calendar
    ADD CONSTRAINT campaign_pkey PRIMARY KEY (id);


--
-- Name: campaign campaign_pkey1; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign
    ADD CONSTRAINT campaign_pkey1 PRIMARY KEY (id);


--
-- Name: campaign_recipient campaign_recipient_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_recipient
    ADD CONSTRAINT campaign_recipient_pkey PRIMARY KEY (id);


--
-- Name: campaign_senders_email campaign_senders_email_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_senders_email
    ADD CONSTRAINT campaign_senders_email_pkey PRIMARY KEY (id);


--
-- Name: campaign_variants campaign_variants_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_variants
    ADD CONSTRAINT campaign_variants_pkey PRIMARY KEY (id);


--
-- Name: city_tender_templates city_tender_templates_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.city_tender_templates
    ADD CONSTRAINT city_tender_templates_pkey PRIMARY KEY (id);


--
-- Name: client_email_region_pms client_email_region_pms_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_region_pms
    ADD CONSTRAINT client_email_region_pms_pkey PRIMARY KEY (id);


--
-- Name: client_email_region_pms client_email_region_pms_region_id_email_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_region_pms
    ADD CONSTRAINT client_email_region_pms_region_id_email_key UNIQUE (region_id, email);


--
-- Name: client_email_regions client_email_regions_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_regions
    ADD CONSTRAINT client_email_regions_pkey PRIMARY KEY (region_id);


--
-- Name: client_email_regions client_email_regions_region_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_regions
    ADD CONSTRAINT client_email_regions_region_key UNIQUE (region);


--
-- Name: client_email_templates client_email_templates_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_templates
    ADD CONSTRAINT client_email_templates_pkey PRIMARY KEY (id);


--
-- Name: cokl_inspection_deficiencies cokl_inspection_deficiencies_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_deficiencies
    ADD CONSTRAINT cokl_inspection_deficiencies_pkey PRIMARY KEY (id);


--
-- Name: cokl_inspection_driveways cokl_inspection_driveways_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_driveways
    ADD CONSTRAINT cokl_inspection_driveways_pkey PRIMARY KEY (id);


--
-- Name: cokl_no_report_inspections cokl_no_report_inspections_entry_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_no_report_inspections
    ADD CONSTRAINT cokl_no_report_inspections_entry_id_key UNIQUE (entry_id);


--
-- Name: cokl_no_report_inspections cokl_no_report_inspections_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_no_report_inspections
    ADD CONSTRAINT cokl_no_report_inspections_pkey PRIMARY KEY (id);


--
-- Name: cokl_site_inspections cokl_site_inspections_entry_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_site_inspections
    ADD CONSTRAINT cokl_site_inspections_entry_id_key UNIQUE (entry_id);


--
-- Name: cokl_site_inspections cokl_site_inspections_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_site_inspections
    ADD CONSTRAINT cokl_site_inspections_pkey PRIMARY KEY (id);


--
-- Name: daily_sheet_update daily_sheet_update_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.daily_sheet_update
    ADD CONSTRAINT daily_sheet_update_pkey PRIMARY KEY (id);


--
-- Name: daily_update_log daily_update_log_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.daily_update_log
    ADD CONSTRAINT daily_update_log_pkey PRIMARY KEY (id);


--
-- Name: email_queue email_queue_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.email_queue
    ADD CONSTRAINT email_queue_pkey PRIMARY KEY (id);


--
-- Name: employee_timesheet employee_timesheet_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_timesheet
    ADD CONSTRAINT employee_timesheet_pkey PRIMARY KEY (id);


--
-- Name: invoice_ap invoice_ap_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.invoice_ap
    ADD CONSTRAINT invoice_ap_pkey PRIMARY KEY (invoice_id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (invoice_id);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: lesson_project_links lesson_project_links_lesson_id_project_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lesson_project_links
    ADD CONSTRAINT lesson_project_links_lesson_id_project_id_key UNIQUE (lesson_id, project_id);


--
-- Name: lesson_project_links lesson_project_links_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lesson_project_links
    ADD CONSTRAINT lesson_project_links_pkey PRIMARY KEY (id);


--
-- Name: lessons_learned lessons_learned_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lessons_learned
    ADD CONSTRAINT lessons_learned_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: mam_transportation_inspections mam_transportation_inspections_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.mam_transportation_inspections
    ADD CONSTRAINT mam_transportation_inspections_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (company_id);


--
-- Name: people_activities people_activities_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_activities
    ADD CONSTRAINT people_activities_pkey PRIMARY KEY (activity_id);


--
-- Name: people_conversation people_conversation_people_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_conversation
    ADD CONSTRAINT people_conversation_people_id_key UNIQUE (people_id);


--
-- Name: people_conversation people_conversation_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_conversation
    ADD CONSTRAINT people_conversation_pkey PRIMARY KEY (conversation_id);


--
-- Name: people_notes people_notes_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_notes
    ADD CONSTRAINT people_notes_pkey PRIMARY KEY (note_id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (id);


--
-- Name: people_project_conversation people_project_conversation_people_id_project_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_project_conversation
    ADD CONSTRAINT people_project_conversation_people_id_project_id_key UNIQUE (people_id, project_id);


--
-- Name: people_project_conversation people_project_conversation_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_project_conversation
    ADD CONSTRAINT people_project_conversation_pkey PRIMARY KEY (conversation_id);


--
-- Name: people_reminders people_reminders_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.people_reminders
    ADD CONSTRAINT people_reminders_pkey PRIMARY KEY (reminder_id);


--
-- Name: pmis_module_access pmis_module_access_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.pmis_module_access
    ADD CONSTRAINT pmis_module_access_pkey PRIMARY KEY (id);


--
-- Name: po_approval_tokens po_approval_tokens_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.po_approval_tokens
    ADD CONSTRAINT po_approval_tokens_pkey PRIMARY KEY (token_id);


--
-- Name: po_approval_tokens po_approval_tokens_token_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.po_approval_tokens
    ADD CONSTRAINT po_approval_tokens_token_key UNIQUE (token);


--
-- Name: privileges privileges_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.privileges
    ADD CONSTRAINT privileges_pkey PRIMARY KEY (user_id, privilege_id);


--
-- Name: processed_events processed_events_event_type_email_campaign_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.processed_events
    ADD CONSTRAINT processed_events_event_type_email_campaign_id_key UNIQUE (event_type, email, campaign_id);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (event_id);


--
-- Name: project_tags project_tags_name_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tags
    ADD CONSTRAINT project_tags_name_key UNIQUE (name);


--
-- Name: project_tags project_tags_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tags
    ADD CONSTRAINT project_tags_pkey PRIMARY KEY (id);


--
-- Name: project_tasklists_map project_tasklists_map_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tasklists_map
    ADD CONSTRAINT project_tasklists_map_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (project_id);


--
-- Name: proposal_clients proposal_clients_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_clients
    ADD CONSTRAINT proposal_clients_pkey PRIMARY KEY (id);


--
-- Name: proposal_company proposal_company_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company
    ADD CONSTRAINT proposal_company_pkey PRIMARY KEY (id);


--
-- Name: proposal_company_profile proposal_company_profile_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_profile
    ADD CONSTRAINT proposal_company_profile_pkey PRIMARY KEY (id);


--
-- Name: proposal_company_projects proposal_company_projects_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_projects
    ADD CONSTRAINT proposal_company_projects_pkey PRIMARY KEY (id);


--
-- Name: proposal_generated_document proposal_generated_document_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_generated_document
    ADD CONSTRAINT proposal_generated_document_pkey PRIMARY KEY (id);


--
-- Name: proposal_generated_document proposal_generated_document_url_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_generated_document
    ADD CONSTRAINT proposal_generated_document_url_key UNIQUE (url);


--
-- Name: proposal_generator_master proposal_generator_master_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_generator_master
    ADD CONSTRAINT proposal_generator_master_pkey PRIMARY KEY (proposal_id);


--
-- Name: proposal_plan proposal_plan_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_plan
    ADD CONSTRAINT proposal_plan_pkey PRIMARY KEY (id);


--
-- Name: proposal_plans proposal_plans_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_plans
    ADD CONSTRAINT proposal_plans_pkey PRIMARY KEY (id);


--
-- Name: proposal_policies proposal_policies_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_policies
    ADD CONSTRAINT proposal_policies_pkey PRIMARY KEY (id);


--
-- Name: proposal_project_experience proposal_project_experience_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_project_experience
    ADD CONSTRAINT proposal_project_experience_pkey PRIMARY KEY (id);


--
-- Name: proposal_step_1 proposal_step_1_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_1
    ADD CONSTRAINT proposal_step_1_pkey PRIMARY KEY (id);


--
-- Name: proposal_step_2 proposal_step_2_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_2
    ADD CONSTRAINT proposal_step_2_pkey PRIMARY KEY (id);


--
-- Name: proposal_step_2 proposal_step_2_proposal_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_2
    ADD CONSTRAINT proposal_step_2_proposal_id_key UNIQUE (proposal_id);


--
-- Name: proposal_step_3 proposal_step_3_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_3
    ADD CONSTRAINT proposal_step_3_pkey PRIMARY KEY (id);


--
-- Name: proposal_step_3 proposal_step_3_proposal_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_3
    ADD CONSTRAINT proposal_step_3_proposal_id_key UNIQUE (proposal_id);


--
-- Name: proposal_step_4 proposal_step_4_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_4
    ADD CONSTRAINT proposal_step_4_pkey PRIMARY KEY (id);


--
-- Name: proposal_step_4 proposal_step_4_proposal_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_4
    ADD CONSTRAINT proposal_step_4_proposal_id_key UNIQUE (proposal_id);


--
-- Name: proposal_sub_consultant proposal_sub_consultant_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_sub_consultant
    ADD CONSTRAINT proposal_sub_consultant_pkey PRIMARY KEY (id);


--
-- Name: proposal_team_detail proposal_team_detail_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_detail
    ADD CONSTRAINT proposal_team_detail_pkey PRIMARY KEY (id);


--
-- Name: proposal_team_member_overrides proposal_team_member_overrides_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member_overrides
    ADD CONSTRAINT proposal_team_member_overrides_pkey PRIMARY KEY (id);


--
-- Name: proposal_team_member_overrides proposal_team_member_overrides_unique; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member_overrides
    ADD CONSTRAINT proposal_team_member_overrides_unique UNIQUE (proposal_id, team_member_id);


--
-- Name: proposal_team_member proposal_team_member_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member
    ADD CONSTRAINT proposal_team_member_pkey PRIMARY KEY (id);


--
-- Name: proposal_team_members proposal_team_members_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_members
    ADD CONSTRAINT proposal_team_members_pkey PRIMARY KEY (id);


--
-- Name: proposal_template_master proposal_template_master_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_template_master
    ADD CONSTRAINT proposal_template_master_pkey PRIMARY KEY (id);


--
-- Name: proposals proposals_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposals
    ADD CONSTRAINT proposals_pkey PRIMARY KEY (proposal_id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (po_id);


--
-- Name: purchase_orders purchase_orders_po_code_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.purchase_orders
    ADD CONSTRAINT purchase_orders_po_code_key UNIQUE (po_code);


--
-- Name: purchase_orders purchase_orders_po_number_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.purchase_orders
    ADD CONSTRAINT purchase_orders_po_number_key UNIQUE (po_number);


--
-- Name: region_comments region_comments_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.region_comments
    ADD CONSTRAINT region_comments_pkey PRIMARY KEY (serial_number);


--
-- Name: rfps rfps_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.rfps
    ADD CONSTRAINT rfps_pkey PRIMARY KEY (rfp_id);


--
-- Name: section section_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.section
    ADD CONSTRAINT section_pkey PRIMARY KEY (id);


--
-- Name: ses_access_management ses_access_management_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ses_access_management
    ADD CONSTRAINT ses_access_management_pkey PRIMARY KEY (id);


--
-- Name: ses_mapping ses_mapping_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ses_mapping
    ADD CONSTRAINT ses_mapping_pkey PRIMARY KEY (id);


--
-- Name: sescampaigntable sescampaigntable_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sescampaigntable
    ADD CONSTRAINT sescampaigntable_pkey PRIMARY KEY (cmpid);


--
-- Name: sestemplatetable sestemplatetable_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sestemplatetable
    ADD CONSTRAINT sestemplatetable_pkey PRIMARY KEY (tmpid);


--
-- Name: shared_folder shared_folder_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.shared_folder
    ADD CONSTRAINT shared_folder_pkey PRIMARY KEY (id);


--
-- Name: sharepoint_folder_structures sharepoint_folder_structures_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sharepoint_folder_structures
    ADD CONSTRAINT sharepoint_folder_structures_pkey PRIMARY KEY (id);


--
-- Name: sharepoint_folder_structures sharepoint_folder_structures_structure_name_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sharepoint_folder_structures
    ADD CONSTRAINT sharepoint_folder_structures_structure_name_key UNIQUE (structure_name);


--
-- Name: specification_items specification_items_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification_items
    ADD CONSTRAINT specification_items_pkey PRIMARY KEY (spec_id, item_id);


--
-- Name: specification specification_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification
    ADD CONSTRAINT specification_pkey PRIMARY KEY (id);


--
-- Name: subconsultants subconsultants_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.subconsultants
    ADD CONSTRAINT subconsultants_pkey PRIMARY KEY (id);


--
-- Name: tasklist_templates tasklist_templates_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasklist_templates
    ADD CONSTRAINT tasklist_templates_pkey PRIMARY KEY (template_id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (task_id);


--
-- Name: template template_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.template
    ADD CONSTRAINT template_pkey PRIMARY KEY (id);


--
-- Name: template_style_config template_style_config_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.template_style_config
    ADD CONSTRAINT template_style_config_pkey PRIMARY KEY (id);


--
-- Name: tender_document_static_sections tender_document_static_sections_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_document_static_sections
    ADD CONSTRAINT tender_document_static_sections_pkey PRIMARY KEY (id);


--
-- Name: tender_document_static_sections tender_document_static_sections_section_key_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_document_static_sections
    ADD CONSTRAINT tender_document_static_sections_section_key_key UNIQUE (section_key);


--
-- Name: tender_item tender_item_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_item
    ADD CONSTRAINT tender_item_pkey PRIMARY KEY (id);


--
-- Name: tender tender_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender
    ADD CONSTRAINT tender_pkey PRIMARY KEY (id);


--
-- Name: terms_conditions terms_conditions_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.terms_conditions
    ADD CONSTRAINT terms_conditions_pkey PRIMARY KEY (tc_id);


--
-- Name: tf_ai_messages tf_ai_messages_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tf_ai_messages
    ADD CONSTRAINT tf_ai_messages_pkey PRIMARY KEY (id);


--
-- Name: tf_ai_sessions tf_ai_sessions_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tf_ai_sessions
    ADD CONSTRAINT tf_ai_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: timesheet timesheet_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.timesheet
    ADD CONSTRAINT timesheet_pkey PRIMARY KEY (id);


--
-- Name: tracker tracker_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tracker
    ADD CONSTRAINT tracker_pkey PRIMARY KEY (tracker_id);


--
-- Name: transmittal_categories transmittal_categories_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittal_categories
    ADD CONSTRAINT transmittal_categories_pkey PRIMARY KEY (id);


--
-- Name: transmittals transmittals_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittals
    ADD CONSTRAINT transmittals_pkey PRIMARY KEY (id);


--
-- Name: ttm_departments ttm_departments_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_departments
    ADD CONSTRAINT ttm_departments_pkey PRIMARY KEY (id);


--
-- Name: ttm_designations ttm_designations_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_designations
    ADD CONSTRAINT ttm_designations_pkey PRIMARY KEY (id);


--
-- Name: ttm_table ttm_table_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ttm_table
    ADD CONSTRAINT ttm_table_pkey PRIMARY KEY (ttm_id);


--
-- Name: campaign_audience unique_campaign_contact; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_audience
    ADD CONSTRAINT unique_campaign_contact UNIQUE (cmpid, contact_email);


--
-- Name: campaign_variants unique_campaign_variant; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_variants
    ADD CONSTRAINT unique_campaign_variant UNIQUE (cmpid, variant_key);


--
-- Name: items unique_item_name; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.items
    ADD CONSTRAINT unique_item_name UNIQUE (item_name);


--
-- Name: section unique_section_name; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.section
    ADD CONSTRAINT unique_section_name UNIQUE (name);


--
-- Name: specification_items unique_spec_item; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification_items
    ADD CONSTRAINT unique_spec_item UNIQUE (spec_id, item_id);


--
-- Name: pmis_module_access unique_user_pmis_access; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.pmis_module_access
    ADD CONSTRAINT unique_user_pmis_access UNIQUE (user_id);


--
-- Name: project_tasklists_map uq_project_subdepartment; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tasklists_map
    ADD CONSTRAINT uq_project_subdepartment UNIQUE (project_id, subdepartment_id);


--
-- Name: transmittals uq_transmittal_no_per_project; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittals
    ADD CONSTRAINT uq_transmittal_no_per_project UNIQUE (project_id, transmittal_no);


--
-- Name: user_fcm_tokens user_fcm_tokens_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_pkey PRIMARY KEY (id);


--
-- Name: user_fcm_tokens user_fcm_tokens_user_id_fcm_token_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_user_id_fcm_token_key UNIQUE (user_id, fcm_token);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: fki_F; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX "fki_F" ON schema_3.users USING btree (dept_id);


--
-- Name: fki_fk_user_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX fki_fk_user_manager ON schema_3.users USING btree (direct_manager_id);


--
-- Name: fki_fk_users_dept; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX fki_fk_users_dept ON schema_3.users USING btree (dept_id);


--
-- Name: fki_fk_users_jobtitle; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX fki_fk_users_jobtitle ON schema_3.users USING btree (job_id);


--
-- Name: fki_fk_users_projdept; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX fki_fk_users_projdept ON schema_3.users USING btree (dept_id);


--
-- Name: fki_users_jobtitle; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX fki_users_jobtitle ON schema_3.users USING btree (job_id);


--
-- Name: idx_ab_events_campaign; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ab_events_campaign ON schema_3.ab_email_events USING btree (cmpid);


--
-- Name: idx_ab_events_ses_message; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ab_events_ses_message ON schema_3.ab_email_events USING btree (ses_message_id);


--
-- Name: idx_ab_events_type; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ab_events_type ON schema_3.ab_email_events USING btree (cmpid, event_type);


--
-- Name: idx_ab_events_variant; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ab_events_variant ON schema_3.ab_email_events USING btree (variant_id);


--
-- Name: idx_audience_campaign; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_campaign ON schema_3.campaign_audience USING btree (cmpid);


--
-- Name: idx_audience_email; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_email ON schema_3.campaign_audience USING btree (contact_email);


--
-- Name: idx_audience_ses_message; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_ses_message ON schema_3.campaign_audience USING btree (ses_message_id);


--
-- Name: idx_audience_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_status ON schema_3.campaign_audience USING btree (cmpid, status);


--
-- Name: idx_audience_test_group; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_test_group ON schema_3.campaign_audience USING btree (cmpid, is_test_group);


--
-- Name: idx_audience_variant; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_audience_variant ON schema_3.campaign_audience USING btree (variant_id);


--
-- Name: idx_auto_emails_enrollment; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_auto_emails_enrollment ON schema_3.automation_emails USING btree (enrollment_id);


--
-- Name: idx_auto_emails_ses; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_auto_emails_ses ON schema_3.automation_emails USING btree (ses_message_id) WHERE (ses_message_id IS NOT NULL);


--
-- Name: idx_auto_logs_enrollment; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_auto_logs_enrollment ON schema_3.automation_logs USING btree (enrollment_id);


--
-- Name: idx_automation_flows_cmpid; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_automation_flows_cmpid ON schema_3.automation_flows USING btree (cmpid);


--
-- Name: idx_campaign_recipient_bounce_type; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_bounce_type ON schema_3.campaign_recipient USING btree (bounce_type) WHERE (bounce_type IS NOT NULL);


--
-- Name: idx_campaign_recipient_campaign_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_campaign_id ON schema_3.campaign_recipient USING btree (campaign_id);


--
-- Name: idx_campaign_recipient_campaign_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_campaign_status ON schema_3.campaign_recipient USING btree (campaign_id, status);


--
-- Name: idx_campaign_recipient_complaint; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_complaint ON schema_3.campaign_recipient USING btree (complaint) WHERE (complaint = true);


--
-- Name: idx_campaign_recipient_ses_message_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_ses_message_id ON schema_3.campaign_recipient USING btree (ses_message_id);


--
-- Name: idx_campaign_recipient_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_campaign_recipient_status ON schema_3.campaign_recipient USING btree (status);


--
-- Name: idx_cokl_deficiencies_assigned; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_deficiencies_assigned ON schema_3.cokl_inspection_deficiencies USING btree (assigned_to);


--
-- Name: idx_cokl_deficiencies_inspection; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_deficiencies_inspection ON schema_3.cokl_inspection_deficiencies USING btree (inspection_id);


--
-- Name: idx_cokl_deficiencies_severity; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_deficiencies_severity ON schema_3.cokl_inspection_deficiencies USING btree (severity);


--
-- Name: idx_cokl_driveways_inspection; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_driveways_inspection ON schema_3.cokl_inspection_driveways USING btree (inspection_id);


--
-- Name: idx_cokl_driveways_uid; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_driveways_uid ON schema_3.cokl_inspection_driveways USING btree (uid);


--
-- Name: idx_cokl_inspections_area; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_area ON schema_3.cokl_site_inspections USING btree (area_code);


--
-- Name: idx_cokl_inspections_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_date ON schema_3.cokl_site_inspections USING btree (inspection_date);


--
-- Name: idx_cokl_inspections_entry_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_entry_id ON schema_3.cokl_site_inspections USING btree (entry_id);


--
-- Name: idx_cokl_inspections_inspector; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_inspector ON schema_3.cokl_site_inspections USING btree (inspector);


--
-- Name: idx_cokl_inspections_jde_project; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_jde_project ON schema_3.cokl_site_inspections USING btree (jde_project_id);


--
-- Name: idx_cokl_inspections_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_status ON schema_3.cokl_site_inspections USING btree (task_status);


--
-- Name: idx_cokl_inspections_submitted; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_cokl_inspections_submitted ON schema_3.cokl_site_inspections USING btree (submitted_at);


--
-- Name: idx_enrollments_flow; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_enrollments_flow ON schema_3.automation_enrollments USING btree (flow_id);


--
-- Name: idx_enrollments_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_enrollments_status ON schema_3.automation_enrollments USING btree (status);


--
-- Name: idx_enrollments_waiting; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_enrollments_waiting ON schema_3.automation_enrollments USING btree (waiting_until) WHERE ((status)::text = 'waiting'::text);


--
-- Name: idx_ll_categories; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ll_categories ON schema_3.lessons_learned USING gin (categories);


--
-- Name: idx_ll_project; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ll_project ON schema_3.lessons_learned USING btree (project_id);


--
-- Name: idx_ll_type_tags; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ll_type_tags ON schema_3.lessons_learned USING gin (project_type_tags);


--
-- Name: idx_lpl_lesson; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_lpl_lesson ON schema_3.lesson_project_links USING btree (lesson_id);


--
-- Name: idx_lpl_project; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_lpl_project ON schema_3.lesson_project_links USING btree (project_id);


--
-- Name: idx_no_report_area; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_no_report_area ON schema_3.cokl_no_report_inspections USING btree (area_code);


--
-- Name: idx_no_report_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_no_report_date ON schema_3.cokl_no_report_inspections USING btree (visit_date);


--
-- Name: idx_no_report_entry_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_no_report_entry_id ON schema_3.cokl_no_report_inspections USING btree (entry_id);


--
-- Name: idx_no_report_inspector; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_no_report_inspector ON schema_3.cokl_no_report_inspections USING btree (inspector);


--
-- Name: idx_pmis_access_granted; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_pmis_access_granted ON schema_3.pmis_module_access USING btree (access_granted);


--
-- Name: idx_pmis_access_revoked; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_pmis_access_revoked ON schema_3.pmis_module_access USING btree (revoked);


--
-- Name: idx_pmis_access_user_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_pmis_access_user_id ON schema_3.pmis_module_access USING btree (user_id);


--
-- Name: idx_proposal_generator_master_active; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_proposal_generator_master_active ON schema_3.proposal_generator_master USING btree (is_active);


--
-- Name: idx_proposal_generator_master_city; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_proposal_generator_master_city ON schema_3.proposal_generator_master USING btree (city_id);


--
-- Name: idx_proposal_generator_master_client; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_proposal_generator_master_client ON schema_3.proposal_generator_master USING btree (client_id);


--
-- Name: idx_proposal_generator_master_department_ids; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_proposal_generator_master_department_ids ON schema_3.proposal_generator_master USING gin (department_ids);


--
-- Name: idx_proposal_generator_master_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_proposal_generator_master_status ON schema_3.proposal_generator_master USING btree (status);


--
-- Name: idx_ptm_project_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ptm_project_id ON schema_3.project_tasklists_map USING btree (project_id);


--
-- Name: idx_ptm_subdepartment_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_ptm_subdepartment_id ON schema_3.project_tasklists_map USING btree (subdepartment_id);


--
-- Name: idx_recipient_ses_message; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_recipient_ses_message ON schema_3.campaign_recipient USING btree (ses_message_id);


--
-- Name: idx_recipient_test_group; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_recipient_test_group ON schema_3.campaign_recipient USING btree (campaign_id, is_test_group);


--
-- Name: idx_recipient_variant; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_recipient_variant ON schema_3.campaign_recipient USING btree (variant_id);


--
-- Name: idx_schema_3_tasks_assigned_to; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_assigned_to ON schema_3.tasks USING btree (assigned_to);


--
-- Name: idx_schema_3_tasks_dependent_on_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_dependent_on_id ON schema_3.tasks USING btree (dependent_on_id) WHERE ((dependent_on_type)::text = 'Task'::text);


--
-- Name: idx_schema_3_tasks_due_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_due_date ON schema_3.tasks USING btree (due_date) WHERE (due_date IS NOT NULL);


--
-- Name: idx_schema_3_tasks_group_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_group_id ON schema_3.tasks USING btree (group_id) WHERE (group_id IS NOT NULL);


--
-- Name: idx_schema_3_tasks_parent_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_parent_id ON schema_3.tasks USING btree (parent_id) WHERE (parent_id IS NOT NULL);


--
-- Name: idx_schema_3_tasks_request_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_request_manager ON schema_3.tasks USING btree (assigned_by) WHERE (is_requested = true);


--
-- Name: idx_schema_3_tasks_requested_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_requested_by ON schema_3.tasks USING btree (requested_by) WHERE (is_requested = true);


--
-- Name: idx_schema_3_tasks_start_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_schema_3_tasks_start_date ON schema_3.tasks USING btree (start_date) WHERE (start_date IS NOT NULL);


--
-- Name: idx_sharepoint_folder_structures_data; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sharepoint_folder_structures_data ON schema_3.sharepoint_folder_structures USING gin (structure_data);


--
-- Name: idx_sharepoint_folder_structures_name; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sharepoint_folder_structures_name ON schema_3.sharepoint_folder_structures USING btree (structure_name);


--
-- Name: idx_tasklist_templates_subdept; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_tasklist_templates_subdept ON schema_3.tasklist_templates USING btree (subdepartment_id);


--
-- Name: idx_tf_ai_messages_session_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_tf_ai_messages_session_id ON schema_3.tf_ai_messages USING btree (session_id);


--
-- Name: idx_tf_ai_sessions_user_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_tf_ai_sessions_user_id ON schema_3.tf_ai_sessions USING btree (user_id);


--
-- Name: idx_trn_insp_asset_db_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_trn_insp_asset_db_id ON schema_3.mam_transportation_inspections USING btree (asset_db_id);


--
-- Name: idx_trn_insp_asset_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_trn_insp_asset_id ON schema_3.mam_transportation_inspections USING btree (asset_id);


--
-- Name: idx_trn_insp_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_trn_insp_date ON schema_3.mam_transportation_inspections USING btree (inspection_date DESC);


--
-- Name: idx_trn_insp_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_trn_insp_status ON schema_3.mam_transportation_inspections USING btree (status);


--
-- Name: idx_trn_insp_type; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_trn_insp_type ON schema_3.mam_transportation_inspections USING btree (inspection_type);


--
-- Name: idx_user_fcm_tokens_user_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_user_fcm_tokens_user_id ON schema_3.user_fcm_tokens USING btree (user_id);


--
-- Name: idx_users_user_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_users_user_id ON schema_3.users USING btree (user_id);


--
-- Name: idx_variants_campaign; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_variants_campaign ON schema_3.campaign_variants USING btree (cmpid);


--
-- Name: idx_variants_key; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_variants_key ON schema_3.campaign_variants USING btree (cmpid, variant_key);


--
-- Name: projects_is_deleted_idx; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX projects_is_deleted_idx ON schema_3.projects USING btree (is_deleted) WHERE (is_deleted = false);


--
-- Name: ttm_departments_name_idx; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX ttm_departments_name_idx ON schema_3.ttm_departments USING btree (lower(btrim(name)));


--
-- Name: ttm_designations_name_idx; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX ttm_designations_name_idx ON schema_3.ttm_designations USING btree (lower(btrim(name)));


--
-- Name: uq_campaign_senders_email_lower; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE UNIQUE INDEX uq_campaign_senders_email_lower ON schema_3.campaign_senders_email USING btree (lower((email)::text));


--
-- Name: uq_transmittal_category_name_lower; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE UNIQUE INDEX uq_transmittal_category_name_lower ON schema_3.transmittal_categories USING btree (lower((name)::text));


--
-- Name: cokl_site_inspections trigger_update_cokl_inspection_timestamp; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_update_cokl_inspection_timestamp BEFORE UPDATE ON schema_3.cokl_site_inspections FOR EACH ROW EXECUTE FUNCTION schema_3.update_cokl_inspection_timestamp();


--
-- Name: pmis_module_access trigger_update_pmis_access_timestamp; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_update_pmis_access_timestamp BEFORE UPDATE ON schema_3.pmis_module_access FOR EACH ROW EXECUTE FUNCTION schema_3.update_pmis_access_timestamp();


--
-- Name: template_style_config trigger_update_template_style_config_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_update_template_style_config_updated_at BEFORE UPDATE ON schema_3.template_style_config FOR EACH ROW EXECUTE FUNCTION public.update_template_style_config_updated_at();


--
-- Name: sharepoint_folder_structures update_sharepoint_folder_structures_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_sharepoint_folder_structures_updated_at BEFORE UPDATE ON schema_3.sharepoint_folder_structures FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ab_email_events ab_email_events_cmpid_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ab_email_events
    ADD CONSTRAINT ab_email_events_cmpid_fkey FOREIGN KEY (cmpid) REFERENCES schema_3.sescampaigntable(cmpid) ON DELETE CASCADE;


--
-- Name: ab_email_events ab_email_events_variant_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.ab_email_events
    ADD CONSTRAINT ab_email_events_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES schema_3.campaign_variants(id) ON DELETE SET NULL;


--
-- Name: automation_emails automation_emails_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_emails
    ADD CONSTRAINT automation_emails_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES schema_3.automation_enrollments(id) ON DELETE CASCADE;


--
-- Name: automation_enrollments automation_enrollments_flow_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_enrollments
    ADD CONSTRAINT automation_enrollments_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES schema_3.automation_flows(id) ON DELETE CASCADE;


--
-- Name: automation_enrollments automation_enrollments_recipient_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_enrollments
    ADD CONSTRAINT automation_enrollments_recipient_id_fkey FOREIGN KEY (audience_id) REFERENCES schema_3.campaign_recipient(id) ON DELETE CASCADE;


--
-- Name: automation_flows automation_flows_cmpid_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_flows
    ADD CONSTRAINT automation_flows_cmpid_fkey FOREIGN KEY (cmpid) REFERENCES schema_3.campaign(id) ON DELETE CASCADE;


--
-- Name: automation_logs automation_logs_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.automation_logs
    ADD CONSTRAINT automation_logs_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES schema_3.automation_enrollments(id) ON DELETE CASCADE;


--
-- Name: campaign_audience campaign_audience_cmpid_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_audience
    ADD CONSTRAINT campaign_audience_cmpid_fkey FOREIGN KEY (cmpid) REFERENCES schema_3.sescampaigntable(cmpid) ON DELETE CASCADE;


--
-- Name: campaign_audience campaign_audience_variant_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_audience
    ADD CONSTRAINT campaign_audience_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES schema_3.campaign_variants(id) ON DELETE SET NULL;


--
-- Name: campaign_recipient campaign_recipient_variant_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.campaign_recipient
    ADD CONSTRAINT campaign_recipient_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES schema_3.campaign_variants(id) ON DELETE SET NULL;


--
-- Name: client_email_region_pms client_email_region_pms_region_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_region_pms
    ADD CONSTRAINT client_email_region_pms_region_id_fkey FOREIGN KEY (region_id) REFERENCES schema_3.client_email_regions(region_id) ON DELETE CASCADE;


--
-- Name: client_email_templates client_email_templates_region_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.client_email_templates
    ADD CONSTRAINT client_email_templates_region_id_fkey FOREIGN KEY (region_id) REFERENCES schema_3.client_email_regions(region_id) ON DELETE RESTRICT;


--
-- Name: cokl_inspection_deficiencies cokl_inspection_deficiencies_inspection_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_deficiencies
    ADD CONSTRAINT cokl_inspection_deficiencies_inspection_id_fkey FOREIGN KEY (inspection_id) REFERENCES schema_3.cokl_site_inspections(id) ON DELETE CASCADE;


--
-- Name: cokl_inspection_driveways cokl_inspection_driveways_inspection_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.cokl_inspection_driveways
    ADD CONSTRAINT cokl_inspection_driveways_inspection_id_fkey FOREIGN KEY (inspection_id) REFERENCES schema_3.cokl_site_inspections(id) ON DELETE CASCADE;


--
-- Name: daily_sheet_update daily_sheet_update_users_fk; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.daily_sheet_update
    ADD CONSTRAINT daily_sheet_update_users_fk FOREIGN KEY (user_id) REFERENCES schema_3.users(user_id) NOT VALID;


--
-- Name: invoices fk_invoices_project_id; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.invoices
    ADD CONSTRAINT fk_invoices_project_id FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id);


--
-- Name: privileges fk_privileges_privilege_id; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.privileges
    ADD CONSTRAINT fk_privileges_privilege_id FOREIGN KEY (privilege_id) REFERENCES public.privileges(privilege_id);


--
-- Name: projects fk_projects_subdepartment; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.projects
    ADD CONSTRAINT fk_projects_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id) NOT VALID;


--
-- Name: proposals fk_proposals_subdepartment; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposals
    ADD CONSTRAINT fk_proposals_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id) NOT VALID;


--
-- Name: rfps fk_rfps_subdepartment; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.rfps
    ADD CONSTRAINT fk_rfps_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id) NOT VALID;


--
-- Name: subconsultants fk_subconsultants_company; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.subconsultants
    ADD CONSTRAINT fk_subconsultants_company FOREIGN KEY (company_id) REFERENCES schema_3.organization(company_id);


--
-- Name: subconsultants fk_subconsultants_project; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.subconsultants
    ADD CONSTRAINT fk_subconsultants_project FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id);


--
-- Name: tasks fk_tasks_assigned_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasks
    ADD CONSTRAINT fk_tasks_assigned_by FOREIGN KEY (assigned_by) REFERENCES schema_3.users(user_id);


--
-- Name: tasks fk_tasks_assigned_to; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasks
    ADD CONSTRAINT fk_tasks_assigned_to FOREIGN KEY (assigned_to) REFERENCES schema_3.users(user_id);


--
-- Name: tasks fk_tasks_reviewed_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tasks
    ADD CONSTRAINT fk_tasks_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES schema_3.users(user_id);


--
-- Name: proposal_step_1 fk_template_id; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_1
    ADD CONSTRAINT fk_template_id FOREIGN KEY (template_id) REFERENCES schema_3.proposal_template_master(id) ON DELETE SET NULL;


--
-- Name: transmittals fk_transmittals_project; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.transmittals
    ADD CONSTRAINT fk_transmittals_project FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id) ON DELETE CASCADE;


--
-- Name: users fk_user_manager; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users
    ADD CONSTRAINT fk_user_manager FOREIGN KEY (direct_manager_id) REFERENCES schema_3.users(user_id);


--
-- Name: users fk_users_auth; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users
    ADD CONSTRAINT fk_users_auth FOREIGN KEY (auth_id) REFERENCES public.auth(user_id);


--
-- Name: users fk_users_dept; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users
    ADD CONSTRAINT fk_users_dept FOREIGN KEY (dept_id) REFERENCES public.project_departments(department_id);


--
-- Name: users fk_users_jobtitle; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.users
    ADD CONSTRAINT fk_users_jobtitle FOREIGN KEY (job_id) REFERENCES public.job_title(job_id);


--
-- Name: sescampaigntable fk_winner_variant; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sescampaigntable
    ADD CONSTRAINT fk_winner_variant FOREIGN KEY (winner_variant_id) REFERENCES schema_3.campaign_variants(id) ON DELETE SET NULL;


--
-- Name: lesson_project_links lesson_project_links_lesson_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lesson_project_links
    ADD CONSTRAINT lesson_project_links_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES schema_3.lessons_learned(id) ON DELETE CASCADE;


--
-- Name: lesson_project_links lesson_project_links_project_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lesson_project_links
    ADD CONSTRAINT lesson_project_links_project_id_fkey FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id) ON DELETE CASCADE;


--
-- Name: lessons_learned lessons_learned_project_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.lessons_learned
    ADD CONSTRAINT lessons_learned_project_id_fkey FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id) ON DELETE CASCADE;


--
-- Name: po_approval_tokens po_approval_tokens_po_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.po_approval_tokens
    ADD CONSTRAINT po_approval_tokens_po_id_fkey FOREIGN KEY (po_id) REFERENCES schema_3.purchase_orders(po_id) ON DELETE CASCADE;


--
-- Name: project_tasklists_map project_tasklists_map_project_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tasklists_map
    ADD CONSTRAINT project_tasklists_map_project_id_fkey FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id);


--
-- Name: project_tasklists_map project_tasklists_map_template_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_tasklists_map
    ADD CONSTRAINT project_tasklists_map_template_id_fkey FOREIGN KEY (template_id) REFERENCES schema_3.tasklist_templates(template_id);


--
-- Name: proposal_company_profile proposal_company_profile_company_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_profile
    ADD CONSTRAINT proposal_company_profile_company_id_fkey FOREIGN KEY (company_id) REFERENCES schema_3.proposal_company(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: proposal_company_projects proposal_company_projects_company_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_projects
    ADD CONSTRAINT proposal_company_projects_company_id_fkey FOREIGN KEY (company_id) REFERENCES schema_3.proposal_company(id);


--
-- Name: proposal_company_projects proposal_company_projects_department_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_projects
    ADD CONSTRAINT proposal_company_projects_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.project_departments(department_id);


--
-- Name: proposal_company_projects proposal_company_projects_project_cat_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_projects
    ADD CONSTRAINT proposal_company_projects_project_cat_id_fkey FOREIGN KEY (project_cat_id) REFERENCES public.project_category(project_cat_id);


--
-- Name: proposal_company_projects proposal_company_projects_subdepartment_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_company_projects
    ADD CONSTRAINT proposal_company_projects_subdepartment_id_fkey FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id);


--
-- Name: proposal_project_experience proposal_project_experience_client_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_project_experience
    ADD CONSTRAINT proposal_project_experience_client_id_fkey FOREIGN KEY (client_id) REFERENCES schema_3.proposal_clients(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: proposal_step_1 proposal_step_1_proposal_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_1
    ADD CONSTRAINT proposal_step_1_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES schema_3.proposal_generator_master(proposal_id) ON DELETE CASCADE;


--
-- Name: proposal_step_3 proposal_step_3_proposal_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_3
    ADD CONSTRAINT proposal_step_3_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES schema_3.proposal_generator_master(proposal_id) ON DELETE CASCADE;


--
-- Name: proposal_step_4 proposal_step_4_proposal_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_step_4
    ADD CONSTRAINT proposal_step_4_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES schema_3.proposal_generator_master(proposal_id) ON DELETE CASCADE;


--
-- Name: proposal_team_member proposal_team_member_company_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member
    ADD CONSTRAINT proposal_team_member_company_id_fkey FOREIGN KEY (company_id) REFERENCES schema_3.proposal_company(id);


--
-- Name: proposal_team_members proposal_team_members_company_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_members
    ADD CONSTRAINT proposal_team_members_company_id_fkey FOREIGN KEY (company_id) REFERENCES schema_3.proposal_company(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: proposal_team_member_overrides proposal_tm_overrides_proposal_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member_overrides
    ADD CONSTRAINT proposal_tm_overrides_proposal_fkey FOREIGN KEY (proposal_id) REFERENCES schema_3.proposal_generator_master(proposal_id) ON DELETE CASCADE;


--
-- Name: proposal_team_member_overrides proposal_tm_overrides_team_member_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.proposal_team_member_overrides
    ADD CONSTRAINT proposal_tm_overrides_team_member_fkey FOREIGN KEY (team_member_id) REFERENCES schema_3.proposal_team_member(id) ON DELETE CASCADE;


--
-- Name: purchase_orders purchase_orders_project_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.purchase_orders
    ADD CONSTRAINT purchase_orders_project_id_fkey FOREIGN KEY (project_id) REFERENCES schema_3.projects(project_id);


--
-- Name: shared_folder shared_folder_subdepartment_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.shared_folder
    ADD CONSTRAINT shared_folder_subdepartment_fkey FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id);


--
-- Name: specification_items specification_items_item_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification_items
    ADD CONSTRAINT specification_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES schema_3.items(id) ON DELETE CASCADE;


--
-- Name: specification_items specification_items_spec_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification_items
    ADD CONSTRAINT specification_items_spec_id_fkey FOREIGN KEY (spec_id) REFERENCES schema_3.specification(id) ON DELETE CASCADE;


--
-- Name: specification specification_section_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.specification
    ADD CONSTRAINT specification_section_id_fkey FOREIGN KEY (section_id) REFERENCES schema_3.section(id);


--
-- Name: tender_item tender_item_tender_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tender_item
    ADD CONSTRAINT tender_item_tender_id_fkey FOREIGN KEY (tender_id) REFERENCES schema_3.tender(id);


--
-- Name: tf_ai_messages tf_ai_messages_session_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tf_ai_messages
    ADD CONSTRAINT tf_ai_messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES schema_3.tf_ai_sessions(session_id) ON DELETE CASCADE;


--
-- Name: tracker tracker_user_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.tracker
    ADD CONSTRAINT tracker_user_id_fkey FOREIGN KEY (user_id) REFERENCES schema_3.users(user_id);


--
-- PostgreSQL database dump complete
--

\unrestrict nVYzhkzkAej25U6KuSa5Kwo9Z2mEuDV7xJIORZDIf9EmqBseHKQL9i6kQLeR7vD

