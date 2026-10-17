--
-- PostgreSQL database dump
--

\restrict wrCj57LlsGOBQxySdXOH3jJ6jyPgtN9NTaf02HS1PaBApZ6PnymHwFLwob0he7b

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: campaignstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.campaignstatus AS ENUM (
    'created',
    'running',
    'delivered',
    'scheduled',
    'failed',
    'paused',
    'completed',
    'sending_winner',
    'ab_testing'
);


--
-- Name: contactstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contactstatus AS ENUM (
    'active',
    'inactive',
    'unsubscribe'
);


--
-- Name: organizationstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.organizationstatus AS ENUM (
    'active',
    'inactive',
    'unsubscribe'
);


--
-- Name: templatestatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.templatestatus AS ENUM (
    'active',
    'inactive',
    'used'
);


--
-- Name: add_ids_to_structure(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_ids_to_structure(structure jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    folder JSONB;
    result JSONB := '[]'::JSONB;
    updated_folder JSONB;
BEGIN
    -- Loop through each folder in the structure array
    FOR folder IN SELECT jsonb_array_elements(structure)
    LOOP
        -- Add UUID to the folder if it doesn't have one
        updated_folder := folder;
        
        -- Add ID if not present
        IF NOT (folder ? 'id') THEN
            updated_folder := updated_folder || jsonb_build_object('id', uuid_generate_v4()::text);
        END IF;
        
        -- Recursively process subfolders if they exist
        IF folder ? 'subfolders' AND jsonb_typeof(folder->'subfolders') = 'array' THEN
            updated_folder := updated_folder || jsonb_build_object(
                'subfolders', 
                add_ids_to_structure(folder->'subfolders')
            );
        END IF;
        
        -- Add the updated folder to result array
        result := result || jsonb_build_array(updated_folder);
    END LOOP;
    
    RETURN result;
END;
$$;


--
-- Name: structure_has_ids(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.structure_has_ids(structure jsonb) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    folder JSONB;
BEGIN
    -- Loop through each folder in the structure array
    FOR folder IN SELECT jsonb_array_elements(structure)
    LOOP
        -- If any folder has an ID, return true
        IF folder ? 'id' THEN
            RETURN TRUE;
        END IF;
        
        -- Check subfolders recursively
        IF folder ? 'subfolders' AND jsonb_typeof(folder->'subfolders') = 'array' THEN
            IF structure_has_ids(folder->'subfolders') THEN
                RETURN TRUE;
            END IF;
        END IF;
    END LOOP;
    
    RETURN FALSE;
END;
$$;


--
-- Name: update_last_updated_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_last_updated_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Set the last_update column to the current timestamp
    NEW.last_updated = CURRENT_TIMESTAMP;  -- Or you can use NOW() as well
    RETURN NEW;
END;
$$;


--
-- Name: update_template_style_config_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_template_style_config_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth (
    user_id integer NOT NULL,
    tenent_id integer,
    email character varying(255),
    password character varying(255)
);


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth.user_id;


--
-- Name: budget_cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.budget_cities (
    city_budget_id integer NOT NULL,
    city_id integer,
    year_22 text,
    website_22 text,
    year_23 text,
    website_23 text,
    remarks text,
    website text,
    year_24 text,
    website_24 text,
    year_25 text,
    website_25 text,
    year_26 text,
    website_26 text,
    year_27 text,
    website_27 text,
    last_modified timestamp with time zone,
    year_value jsonb,
    website_value jsonb
);


--
-- Name: budget_cities_city_budget_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.budget_cities_city_budget_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: budget_cities_city_budget_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.budget_cities_city_budget_id_seq OWNED BY public.budget_cities.city_budget_id;


--
-- Name: budgets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.budgets (
    budget_id integer NOT NULL,
    city_id integer,
    department_id integer,
    project_cat_id integer,
    project_name character varying(255),
    budget_category character varying(255),
    budget_amount integer,
    budget_year integer,
    source character varying(255),
    serial_no character varying(45),
    subdepartment_id integer,
    last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: budgets_budget_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.budgets_budget_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: budgets_budget_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.budgets_budget_id_seq OWNED BY public.budgets.budget_id;


--
-- Name: bugs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bugs (
    id integer NOT NULL,
    auth_id integer,
    type character varying(20),
    title text,
    description text,
    status character varying(50),
    created_at date
);


--
-- Name: bugs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bugs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bugs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bugs_id_seq OWNED BY public.bugs.id;


--
-- Name: cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cards (
    card_id integer NOT NULL,
    card_name character varying(255),
    card_type character varying(255),
    card_module character varying(255),
    created_by_user boolean DEFAULT false,
    role integer
);


--
-- Name: cards_card_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cards_card_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cards_card_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cards_card_id_seq OWNED BY public.cards.card_id;


--
-- Name: cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cities (
    city_id integer NOT NULL,
    city character varying(100),
    province character varying(100),
    country character varying(100),
    municipality_type character varying(100),
    municipality_status character varying(100),
    geographic_area character varying(100),
    city_coordinates text[],
    geographical_coordinates text[],
    population text,
    website text,
    population_by_year jsonb,
    additional jsonb DEFAULT '{}'::jsonb,
    org_name character varying(255),
    address character varying(255),
    cad_standard_folder_id text
);


--
-- Name: cities_city_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cities_city_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cities_city_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cities_city_id_seq OWNED BY public.cities.city_id;


--
-- Name: tenents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenents (
    tenent_id integer NOT NULL,
    tenent_name character varying(255),
    created_at date,
    company_type character varying(100),
    company_size character varying(20),
    subdomain text,
    folder_id character varying(300),
    storage_provider character varying(30) DEFAULT 'Google Drive'::character varying,
    logo_url character varying(300)
);


--
-- Name: clients_client_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clients_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clients_client_id_seq OWNED BY public.tenents.tenent_id;


--
-- Name: dynamic_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dynamic_modules (
    id integer NOT NULL,
    module_name character varying NOT NULL,
    fields_json jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    created_by character varying,
    updated_by character varying
);


--
-- Name: dynamic_modules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dynamic_modules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dynamic_modules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dynamic_modules_id_seq OWNED BY public.dynamic_modules.id;


--
-- Name: employee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee (
    employee_id integer NOT NULL,
    user_id integer NOT NULL,
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
-- Name: project_departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_departments (
    department_id integer NOT NULL,
    department text,
    manager_id integer,
    department_code character varying(25)
);


--
-- Name: employee_department_department_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_department_department_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_department_department_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_department_department_id_seq OWNED BY public.project_departments.department_id;


--
-- Name: employee_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_employee_id_seq OWNED BY public.employee.employee_id;


--
-- Name: invoice_reminder; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_reminder (
    reminder_id integer NOT NULL,
    tenant_id integer NOT NULL,
    schema_name character varying(100) NOT NULL,
    invoice_id integer NOT NULL,
    invoice_code character varying(100),
    reminder_type character varying(50) DEFAULT 'manual'::character varying,
    sent_to_email character varying(255) NOT NULL,
    sent_by_user integer,
    reminder_day integer,
    email_status character varying(50) DEFAULT 'sent'::character varying,
    date_sent timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: invoice_reminder_reminder_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoice_reminder_reminder_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoice_reminder_reminder_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoice_reminder_reminder_id_seq OWNED BY public.invoice_reminder.reminder_id;


--
-- Name: job_title; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_title (
    job_id integer NOT NULL,
    job_title character varying(300)
);


--
-- Name: job_title_job_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.job_title_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: job_title_job_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.job_title_job_id_seq OWNED BY public.job_title.job_id;


--
-- Name: organization_department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_department (
    id integer NOT NULL,
    department_name text NOT NULL
);


--
-- Name: organization_department_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organization_department_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_department_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organization_department_id_seq OWNED BY public.organization_department.id;


--
-- Name: organization_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_label (
    id integer NOT NULL,
    label character varying(20)
);


--
-- Name: organization_label_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organization_label_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_label_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organization_label_id_seq OWNED BY public.organization_label.id;


--
-- Name: otps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otps (
    email character varying(255) NOT NULL,
    otp character varying(10),
    expiry timestamp without time zone
);


--
-- Name: privileges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.privileges (
    privilege_id character varying(50) NOT NULL,
    module character varying(255) NOT NULL,
    privilege character varying(20) NOT NULL
);


--
-- Name: project_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_category (
    project_cat_id integer NOT NULL,
    project_category character varying(255),
    department_id integer,
    sub_department character varying(30),
    subdepartment_id integer
);


--
-- Name: project_category_project_cat_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_category_project_cat_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_category_project_cat_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_category_project_cat_id_seq OWNED BY public.project_category.project_cat_id;


--
-- Name: regioncitymapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.regioncitymapping (
    region_id integer NOT NULL,
    region character varying(255) NOT NULL,
    city character varying(255) NOT NULL,
    city_id integer
);


--
-- Name: regioncitymapping_region_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.regioncitymapping_region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: regioncitymapping_region_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.regioncitymapping_region_id_seq OWNED BY public.regioncitymapping.region_id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    role_id integer NOT NULL,
    role_name character varying,
    cards_id integer[]
);


--
-- Name: roles_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_role_id_seq OWNED BY public.roles.role_id;


--
-- Name: sharepoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sharepoints (
    id integer NOT NULL,
    tenant_id text,
    client_id text,
    client_secret text,
    microsoft_tenant_name text,
    org_id integer NOT NULL
);


--
-- Name: sharepoints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sharepoints_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sharepoints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sharepoints_id_seq OWNED BY public.sharepoints.id;


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    source_id integer NOT NULL,
    source text NOT NULL,
    source_url text
);


--
-- Name: sources_source_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_source_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_source_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_source_id_seq OWNED BY public.sources.source_id;


--
-- Name: sub_department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_department (
    subdepartment_id integer NOT NULL,
    department_id integer,
    manager_id integer,
    subdepartment_name character varying(30),
    subdepartment_code character varying(30),
    sharepoint_site_name character varying(255),
    sharepoint_site_id character varying(300)
);


--
-- Name: sub_department_subdepartment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sub_department_subdepartment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sub_department_subdepartment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sub_department_subdepartment_id_seq OWNED BY public.sub_department.subdepartment_id;


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id integer NOT NULL,
    token character varying(255),
    expires_at timestamp without time zone DEFAULT (CURRENT_TIMESTAMP + '10 days'::interval),
    email character varying(255),
    schema character varying(255),
    invited_by integer
);


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: track; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.track (
    id integer NOT NULL,
    ip text,
    headers jsonb,
    information jsonb,
    module text,
    path text,
    status text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: track_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.track_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: track_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.track_id_seq OWNED BY public.track.id;


--
-- Name: auth user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth ALTER COLUMN user_id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: budget_cities city_budget_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.budget_cities ALTER COLUMN city_budget_id SET DEFAULT nextval('public.budget_cities_city_budget_id_seq'::regclass);


--
-- Name: budgets budget_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.budgets ALTER COLUMN budget_id SET DEFAULT nextval('public.budgets_budget_id_seq'::regclass);


--
-- Name: bugs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bugs ALTER COLUMN id SET DEFAULT nextval('public.bugs_id_seq'::regclass);


--
-- Name: cards card_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cards ALTER COLUMN card_id SET DEFAULT nextval('public.cards_card_id_seq'::regclass);


--
-- Name: cities city_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities ALTER COLUMN city_id SET DEFAULT nextval('public.cities_city_id_seq'::regclass);


--
-- Name: dynamic_modules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_modules ALTER COLUMN id SET DEFAULT nextval('public.dynamic_modules_id_seq'::regclass);


--
-- Name: employee employee_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee ALTER COLUMN employee_id SET DEFAULT nextval('public.employee_employee_id_seq'::regclass);


--
-- Name: invoice_reminder reminder_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_reminder ALTER COLUMN reminder_id SET DEFAULT nextval('public.invoice_reminder_reminder_id_seq'::regclass);


--
-- Name: job_title job_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_title ALTER COLUMN job_id SET DEFAULT nextval('public.job_title_job_id_seq'::regclass);


--
-- Name: organization_department id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_department ALTER COLUMN id SET DEFAULT nextval('public.organization_department_id_seq'::regclass);


--
-- Name: organization_label id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_label ALTER COLUMN id SET DEFAULT nextval('public.organization_label_id_seq'::regclass);


--
-- Name: project_category project_cat_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_category ALTER COLUMN project_cat_id SET DEFAULT nextval('public.project_category_project_cat_id_seq'::regclass);


--
-- Name: project_departments department_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_departments ALTER COLUMN department_id SET DEFAULT nextval('public.employee_department_department_id_seq'::regclass);


--
-- Name: regioncitymapping region_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regioncitymapping ALTER COLUMN region_id SET DEFAULT nextval('public.regioncitymapping_region_id_seq'::regclass);


--
-- Name: roles role_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN role_id SET DEFAULT nextval('public.roles_role_id_seq'::regclass);


--
-- Name: sharepoints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sharepoints ALTER COLUMN id SET DEFAULT nextval('public.sharepoints_id_seq'::regclass);


--
-- Name: sources source_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources ALTER COLUMN source_id SET DEFAULT nextval('public.sources_source_id_seq'::regclass);


--
-- Name: sub_department subdepartment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_department ALTER COLUMN subdepartment_id SET DEFAULT nextval('public.sub_department_subdepartment_id_seq'::regclass);


--
-- Name: tenents tenent_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenents ALTER COLUMN tenent_id SET DEFAULT nextval('public.clients_client_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- Name: track id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.track ALTER COLUMN id SET DEFAULT nextval('public.track_id_seq'::regclass);


--
-- Name: auth auth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth
    ADD CONSTRAINT auth_pkey PRIMARY KEY (user_id);


--
-- Name: budget_cities budget_cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.budget_cities
    ADD CONSTRAINT budget_cities_pkey PRIMARY KEY (city_budget_id);


--
-- Name: budgets budgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.budgets
    ADD CONSTRAINT budgets_pkey PRIMARY KEY (budget_id);


--
-- Name: bugs bugs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bugs
    ADD CONSTRAINT bugs_pkey PRIMARY KEY (id);


--
-- Name: cards cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_pkey PRIMARY KEY (card_id);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (city_id);


--
-- Name: tenents clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenents
    ADD CONSTRAINT clients_pkey PRIMARY KEY (tenent_id);


--
-- Name: dynamic_modules dynamic_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dynamic_modules
    ADD CONSTRAINT dynamic_modules_pkey PRIMARY KEY (id);


--
-- Name: project_departments employee_department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_departments
    ADD CONSTRAINT employee_department_pkey PRIMARY KEY (department_id);


--
-- Name: employee employee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT employee_pkey PRIMARY KEY (employee_id);


--
-- Name: invoice_reminder invoice_reminder_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_reminder
    ADD CONSTRAINT invoice_reminder_pkey PRIMARY KEY (reminder_id);


--
-- Name: job_title job_title_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_title
    ADD CONSTRAINT job_title_pkey PRIMARY KEY (job_id);


--
-- Name: organization_department organization_department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_department
    ADD CONSTRAINT organization_department_pkey PRIMARY KEY (id);


--
-- Name: organization_label organization_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_label
    ADD CONSTRAINT organization_label_pkey PRIMARY KEY (id);


--
-- Name: otps otps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otps
    ADD CONSTRAINT otps_pkey PRIMARY KEY (email);


--
-- Name: privileges privileges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.privileges
    ADD CONSTRAINT privileges_pkey PRIMARY KEY (privilege_id);


--
-- Name: project_category project_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_category
    ADD CONSTRAINT project_category_pkey PRIMARY KEY (project_cat_id);


--
-- Name: regioncitymapping regioncitymapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regioncitymapping
    ADD CONSTRAINT regioncitymapping_pkey PRIMARY KEY (region_id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: sharepoints sharepoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sharepoints
    ADD CONSTRAINT sharepoints_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (source_id);


--
-- Name: sub_department sub_department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_department
    ADD CONSTRAINT sub_department_pkey PRIMARY KEY (subdepartment_id);


--
-- Name: track track_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.track
    ADD CONSTRAINT track_pkey PRIMARY KEY (id);


--
-- Name: cities unique_city_province_country; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT unique_city_province_country UNIQUE (city, province, country);


--
-- Name: budgets set_last_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_last_updated BEFORE UPDATE ON public.budgets FOR EACH ROW EXECUTE FUNCTION public.update_last_updated_column();


--
-- Name: project_category fk_projectcategory_subdepartment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_category
    ADD CONSTRAINT fk_projectcategory_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES public.sub_department(subdepartment_id) NOT VALID;


--
-- Name: sub_department fk_subdepartment_department; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_department
    ADD CONSTRAINT fk_subdepartment_department FOREIGN KEY (department_id) REFERENCES public.project_departments(department_id) NOT VALID;


--
-- Name: employee fk_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES schema_118.users(user_id) ON DELETE CASCADE;


--
-- Name: sharepoints org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sharepoints
    ADD CONSTRAINT org_id FOREIGN KEY (org_id) REFERENCES public.tenents(tenent_id) NOT VALID;


--
-- PostgreSQL database dump complete
--

\unrestrict wrCj57LlsGOBQxySdXOH3jJ6jyPgtN9NTaf02HS1PaBApZ6PnymHwFLwob0he7b

