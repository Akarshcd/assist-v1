--
-- PostgreSQL database dump
--

\restrict gr2dygaSJmMznZYtKYiqjrp1PZBAZD5a9qgoFE8xDPI8Vif11nAnGTcd83mJPbY

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
-- Name: generate_application_id(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.generate_application_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF NEW.application_id IS NULL THEN NEW.application_id = 'APP' || LPAD(nextval('schema_3.application_id_seq')::text, 6, '0'); END IF; RETURN NEW; END; $$;


--
-- Name: sync_scope_on_subdept_move(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.sync_scope_on_subdept_move() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.department_id IS DISTINCT FROM NEW.department_id THEN
        UPDATE schema_3.job_title_scope
        SET department_id = NEW.department_id
        WHERE subdepartment_id = NEW.subdepartment_id
          AND department_id = OLD.department_id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_enforce_test_status(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.trg_enforce_test_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  test_duration INT;
  test_end_date TIMESTAMP;
  total_questions INT;
  answered_questions INT;
BEGIN
  -- Get test duration and end_date from employee_tests
  SELECT duration_seconds, end_date
  INTO test_duration, test_end_date
  FROM schema_3.employee_tests
  WHERE test_id = NEW.test_id;

  -- Count total questions from personality_test_questions
  SELECT COUNT(*) INTO total_questions
  FROM schema_3.personality_test_questions;

  -- Count answered questions for this test
  SELECT COUNT(DISTINCT question_id) INTO answered_questions
  FROM schema_3.personality_test_responses
  WHERE test_id = NEW.test_id AND emp_id = NEW.emp_id;

  -- Condition 1: elapsed_seconds >= duration_seconds => completed
  IF NEW.elapsed_seconds >= test_duration AND NEW.status <> 'completed' THEN
    NEW.status := 'completed';
    NEW.completed_at := NOW();

  -- Condition 2: all questions answered => completed
  ELSIF answered_questions >= total_questions AND NEW.status <> 'completed' THEN
    NEW.status := 'completed';
    NEW.completed_at := NOW();

  -- Condition 3: current time > end_date => expired (only if not already completed)
  ELSIF NOW() > test_end_date AND NEW.status NOT IN ('completed', 'expired') THEN
    NEW.status := 'expired';
    NEW.completed_at := NOW();

  END IF;

  -- If status is completed or expired, create pending score row
  IF NEW.status IN ('completed', 'expired') THEN
    INSERT INTO schema_3.personality_test_scores (
      test_id,
      emp_id,
      status
    ) VALUES (
      NEW.test_id,
      NEW.emp_id,
      'pending'
    ) ON CONFLICT (test_id, emp_id) DO NOTHING;  -- In case it's already created
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: update_interview_timestamps(); Type: FUNCTION; Schema: schema_3; Owner: -
--

CREATE FUNCTION schema_3.update_interview_timestamps() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF TG_OP = 'INSERT' THEN NEW.created_at = now(); NEW.updated_at = now(); ELSIF TG_OP = 'UPDATE' THEN NEW.updated_at = now(); END IF; RETURN NEW; END; $$;


--
-- Name: applicants_applicant_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.applicants_applicant_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: applicants; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.applicants (
    applicant_id integer DEFAULT nextval('schema_3.applicants_applicant_id_seq'::regclass) NOT NULL,
    application_id character varying(20),
    job_id integer NOT NULL,
    applicant_name character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    phone character varying(20),
    date_of_birth date,
    gender character varying(10),
    address character varying(500),
    city character varying(100),
    country character varying(50) DEFAULT 'India'::character varying,
    job_type character varying(50),
    experience character varying(50),
    highest_educational_qualification character varying(100),
    application_date date NOT NULL,
    preferred_joining_date date,
    referral_emp_id integer,
    application_status character varying(30) DEFAULT 'Application Received'::character varying,
    next_interview date,
    documents jsonb DEFAULT '{}'::jsonb,
    portfolio_link character varying(500),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer NOT NULL,
    updated_by integer,
    dept_id integer
);


--
-- Name: application_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.application_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assets_asset_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.assets_asset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assets; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.assets (
    asset_id integer DEFAULT nextval('schema_3.assets_asset_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    asset_name character varying(255) NOT NULL,
    asset_description character varying(255) NOT NULL,
    issue_date date NOT NULL,
    return_date date,
    reason_for_leaving character varying(500),
    asset_type character varying(10),
    asset_condition character varying(255),
    CONSTRAINT assets_asset_type_check CHECK (((asset_type)::text = ANY (ARRAY[('Software'::character varying)::text, ('Hardware'::character varying)::text])))
);


--
-- Name: certificates_cer_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.certificates_cer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: certificates; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.certificates (
    cer_id integer DEFAULT nextval('schema_3.certificates_cer_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255) NOT NULL,
    date date NOT NULL,
    certificate_docs jsonb,
    year integer
);


--
-- Name: company_property; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.company_property (
    property_id integer NOT NULL,
    emp_id integer NOT NULL,
    property_name character varying(255) NOT NULL,
    property_type character varying(50) NOT NULL,
    property_id_code character varying(100),
    description text,
    issue_date date,
    return_date date,
    condition character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_by integer,
    CONSTRAINT company_property_condition_check CHECK (((condition)::text = ANY (ARRAY[('New'::character varying)::text, ('Good'::character varying)::text, ('Fair'::character varying)::text, ('Damaged'::character varying)::text, ('Returned'::character varying)::text]))),
    CONSTRAINT company_property_property_type_check CHECK (((property_type)::text = ANY (ARRAY[('Hardware'::character varying)::text, ('Software'::character varying)::text])))
);


--
-- Name: TABLE company_property; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON TABLE schema_3.company_property IS 'Tracks hardware and software assets assigned to employees';


--
-- Name: COLUMN company_property.property_type; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.company_property.property_type IS 'Type of property: Hardware or Software';


--
-- Name: COLUMN company_property.property_id_code; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.company_property.property_id_code IS 'Unique identifier/serial number for the property';


--
-- Name: COLUMN company_property.condition; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.company_property.condition IS 'Current condition of the asset';


--
-- Name: company_property_property_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.company_property_property_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: company_property_property_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.company_property_property_id_seq OWNED BY schema_3.company_property.property_id;


--
-- Name: employee_bank_details_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_bank_details_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_bank_details; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_bank_details (
    id integer DEFAULT nextval('schema_3.employee_bank_details_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    account_holder_name text,
    account_number text,
    branch_name text,
    bank_name character varying(100),
    bank_ifsc_code text,
    country character varying(50),
    bank_doc jsonb,
    encryption_key_version integer DEFAULT 1,
    encryption_key bytea,
    transit_number text,
    institution_number text,
    interac_id text
);


--
-- Name: employee_contacts_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_contacts; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_contacts (
    id integer DEFAULT nextval('schema_3.employee_contacts_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    name character varying(50),
    mobile character varying(50),
    gender character varying(20),
    relationship character varying(50),
    url character varying(100),
    email_id character varying(50),
    languages text[] DEFAULT '{}'::text[]
);


--
-- Name: COLUMN employee_contacts.languages; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.employee_contacts.languages IS 'Array of languages spoken by the contact';


--
-- Name: employee_offboarding; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_offboarding (
    offboarding_id integer NOT NULL,
    emp_id integer NOT NULL,
    department_id integer,
    manager_id integer,
    date_of_joining date,
    date_of_resignation date,
    notice_period_duration integer,
    estimated_last_working_day date,
    reason_for_resignation text,
    status character varying(50) DEFAULT 'initiated'::character varying,
    created_by integer NOT NULL,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    emp_name character varying(255),
    manager_name character varying(255),
    job_role character varying(255),
    request_type character varying(30),
    department_name character varying(255),
    status_history jsonb DEFAULT '["submitted"]'::jsonb NOT NULL,
    retention_details jsonb DEFAULT '{}'::jsonb,
    termination_details text,
    termination_reason character varying(255),
    rejection_details text,
    CONSTRAINT employee_offboarding_notice_period_duration_check CHECK ((notice_period_duration >= 0)),
    CONSTRAINT employee_offboarding_status_check CHECK (((status)::text = ANY (ARRAY['initiated'::text, 'in_review_manager'::text, 'in_review_hod'::text, 'approved'::text, 'retained'::text, 'retention_initiated'::text, 'terminated'::text, 'in_review_hr'::text, 'pending_termination_approval'::text, 'termination_scheduled'::text, 'termination_cancelled'::text, 'rejected'::text])))
);


--
-- Name: employee_offboarding_offboarding_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_offboarding_offboarding_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_offboarding_offboarding_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.employee_offboarding_offboarding_id_seq OWNED BY schema_3.employee_offboarding.offboarding_id;


--
-- Name: employee_referrals; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_referrals (
    referral_id integer NOT NULL,
    application_id character varying(50) NOT NULL,
    referring_emp_id integer NOT NULL,
    referring_emp_name character varying(255) NOT NULL,
    referring_emp_email character varying(255) NOT NULL,
    candidate_name character varying(255) NOT NULL,
    candidate_email character varying(255) NOT NULL,
    candidate_phone character varying(20),
    date_of_birth date,
    gender character varying(20),
    address text,
    city character varying(100),
    country character varying(100),
    job_id integer,
    experience integer,
    highest_educational_qualification character varying(255),
    application_date date DEFAULT CURRENT_DATE,
    preferred_joining_date date,
    documents jsonb DEFAULT '{}'::jsonb,
    portfolio_link text,
    referral_status character varying(50) DEFAULT 'Pending'::character varying,
    referral_date date DEFAULT CURRENT_DATE,
    status_updated_at timestamp without time zone,
    status_updated_by integer,
    applicant_id integer,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    created_by integer
);


--
-- Name: employee_referrals_referral_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_referrals_referral_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_referrals_referral_id_seq1; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_referrals_referral_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_referrals_referral_id_seq1; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.employee_referrals_referral_id_seq1 OWNED BY schema_3.employee_referrals.referral_id;


--
-- Name: employee_roles; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_roles (
    id integer NOT NULL,
    emp_id integer NOT NULL,
    role_id integer NOT NULL,
    is_primary boolean DEFAULT false,
    finance_scope text[],
    assigned_by integer,
    assigned_at timestamp with time zone DEFAULT now(),
    revoked_at timestamp with time zone,
    CONSTRAINT employee_roles_finance_scope_check CHECK (((finance_scope IS NULL) OR (finance_scope <@ ARRAY['india'::text, 'canada'::text, 'all'::text])))
);


--
-- Name: employee_roles_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.employee_roles_id_seq OWNED BY schema_3.employee_roles.id;


--
-- Name: employee_test_question_order; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_test_question_order (
    test_id integer NOT NULL,
    emp_id integer NOT NULL,
    question_id integer,
    order_no integer NOT NULL
);


--
-- Name: employee_test_sessions; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_test_sessions (
    test_id integer NOT NULL,
    emp_id integer NOT NULL,
    status character varying(20) NOT NULL,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    elapsed_seconds integer DEFAULT 0,
    last_seen timestamp without time zone DEFAULT now(),
    CONSTRAINT employee_test_sessions_status_check CHECK (((status)::text = ANY (ARRAY[('not_started'::character varying)::text, ('in_progress'::character varying)::text, ('completed'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: employee_tests; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.employee_tests (
    test_id integer NOT NULL,
    test_type character varying(20) NOT NULL,
    start_date timestamp without time zone NOT NULL,
    end_date timestamp without time zone NOT NULL,
    duration_seconds integer NOT NULL,
    created_by integer NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT employee_tests_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('completed'::character varying)::text, ('expired'::character varying)::text]))),
    CONSTRAINT employee_tests_test_type_check CHECK (((test_type)::text = 'personality'::text))
);


--
-- Name: employee_tests_test_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.employee_tests_test_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_tests_test_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.employee_tests_test_id_seq OWNED BY schema_3.employee_tests.test_id;


--
-- Name: exit_feedback; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.exit_feedback (
    feedback_id integer NOT NULL,
    offboarding_id integer NOT NULL,
    personal_email_id character varying(255),
    mobile_number character varying(20),
    items_returned jsonb,
    liked_most text,
    improvement_suggestions text,
    would_rejoin boolean,
    company_feedback text,
    join_alumni_network boolean,
    submitted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    experience_ratings jsonb
);


--
-- Name: exit_feedback_feedback_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.exit_feedback_feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exit_feedback_feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.exit_feedback_feedback_id_seq OWNED BY schema_3.exit_feedback.feedback_id;


--
-- Name: holidays_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.holidays_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: holidays; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.holidays (
    id integer DEFAULT nextval('schema_3.holidays_id_seq'::regclass) NOT NULL,
    holiday_name character varying(100) NOT NULL,
    holiday_date date NOT NULL,
    holiday_type character varying(50),
    country character varying(50),
    image_s3_key character varying
);


--
-- Name: hrm_employees_emp_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.hrm_employees_emp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hrm_employees; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.hrm_employees (
    emp_id integer DEFAULT nextval('schema_3.hrm_employees_emp_id_seq'::regclass) NOT NULL,
    crm_id integer NOT NULL,
    dob date,
    address character varying(255),
    gender character varying(50),
    emergency_contact character varying(20),
    bank_details character varying(255),
    position_id integer,
    experience numeric(4,2),
    highest_educational_qualification character varying(255),
    skillset character varying(255)[],
    personal_email character varying(50),
    user_role_id integer DEFAULT 4,
    employee_code character varying(50),
    dept_code character varying(50),
    temp_address character varying(255),
    emergency_contact_relationship character varying(100),
    aadhar jsonb,
    pan jsonb,
    passport jsonb,
    drivers_license jsonb,
    photo jsonb,
    professional_photo jsonb,
    hobbies character varying[],
    country character varying,
    marksheet_12th jsonb,
    degree_certificates jsonb,
    relieving_letter jsonb,
    last_3_payslips jsonb,
    address_proof jsonb,
    immigration_doc jsonb,
    sin jsonb,
    void_check jsonb,
    leave_allocations jsonb,
    auth_id integer,
    software_poc integer,
    languages text[] DEFAULT '{}'::text[],
    is_finance_approver boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: COLUMN hrm_employees.software_poc; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.hrm_employees.software_poc IS 'Stores the user_id of the software Point of Contact for this employee';


--
-- Name: COLUMN hrm_employees.languages; Type: COMMENT; Schema: schema_3; Owner: -
--

COMMENT ON COLUMN schema_3.hrm_employees.languages IS 'Array of languages spoken by the employee';


--
-- Name: hrm_employees_view; Type: VIEW; Schema: schema_3; Owner: -
--

CREATE VIEW schema_3.hrm_employees_view AS
 SELECT hrm_employees.emp_id,
    hrm_employees.crm_id,
    hrm_employees.dob,
    hrm_employees.address,
    hrm_employees.gender,
    hrm_employees.emergency_contact,
    hrm_employees.bank_details,
    hrm_employees.position_id,
    hrm_employees.experience,
    hrm_employees.highest_educational_qualification,
    hrm_employees.skillset,
    hrm_employees.personal_email,
    hrm_employees.user_role_id,
    hrm_employees.employee_code,
    hrm_employees.dept_code,
    hrm_employees.temp_address,
    hrm_employees.emergency_contact_relationship,
    hrm_employees.aadhar,
    hrm_employees.pan,
    hrm_employees.passport,
    hrm_employees.drivers_license,
    hrm_employees.photo,
    hrm_employees.professional_photo,
    hrm_employees.hobbies,
    hrm_employees.country,
    hrm_employees.marksheet_12th,
    hrm_employees.degree_certificates,
    hrm_employees.relieving_letter,
    hrm_employees.last_3_payslips,
    hrm_employees.address_proof,
    hrm_employees.immigration_doc,
    hrm_employees.sin,
    hrm_employees.void_check,
    hrm_employees.leave_allocations,
    hrm_employees.auth_id,
    hrm_employees.software_poc,
    hrm_employees.languages,
    hrm_employees.created_at
   FROM schema_3.hrm_employees;


--
-- Name: interviews; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.interviews (
    interview_id integer NOT NULL,
    applicant_id integer NOT NULL,
    job_id integer NOT NULL,
    hiring_stage_id integer NOT NULL,
    interviewer_ids jsonb NOT NULL,
    meeting_title character varying(255) NOT NULL,
    meeting_date date NOT NULL,
    from_time time without time zone NOT NULL,
    to_time time without time zone NOT NULL,
    timezone character varying(100) DEFAULT 'IST - Indian Standard Time'::character varying,
    meeting_link text,
    microsoft_meeting_id text,
    meeting_notes text,
    status character varying(50) DEFAULT 'scheduled'::character varying,
    feedback jsonb,
    scheduled_by integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: interviews_interview_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.interviews_interview_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: interviews_interview_id_seq1; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.interviews_interview_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: interviews_interview_id_seq1; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.interviews_interview_id_seq1 OWNED BY schema_3.interviews.interview_id;


--
-- Name: job_history_job_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.job_history_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: job_history; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.job_history (
    job_id integer DEFAULT nextval('schema_3.job_history_job_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    company_name character varying(255) NOT NULL,
    job_title character varying(255) NOT NULL,
    start_date date NOT NULL,
    end_date date,
    reason_for_leaving character varying(255),
    employment_type character varying(10),
    job_docs jsonb
);


--
-- Name: job_requests; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.job_requests (
    request_job_id integer NOT NULL,
    requested_by_id integer,
    department_id integer,
    job_title character varying(255) NOT NULL,
    reason text,
    positions integer DEFAULT 1 NOT NULL,
    priority character varying(20),
    work_type character varying(50),
    description text,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_by integer NOT NULL,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    experience character varying(50) DEFAULT '0-1 years'::character varying,
    CONSTRAINT job_requests_priority_check CHECK (((priority)::text = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text]))),
    CONSTRAINT job_requests_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: job_requests_request_job_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.job_requests_request_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: job_requests_request_job_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.job_requests_request_job_id_seq OWNED BY schema_3.job_requests.request_job_id;


--
-- Name: job_title; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.job_title (
    job_id integer NOT NULL,
    job_title character varying(300),
    created_by integer NOT NULL,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    level integer,
    notice_period character varying(50),
    status character varying(20) DEFAULT 'active'::character varying,
    department_id integer,
    subdepartment_id integer
);


--
-- Name: job_title_job_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.job_title_job_id_seq
    START WITH 154
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: job_title_job_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.job_title_job_id_seq OWNED BY schema_3.job_title.job_id;


--
-- Name: leave_policy_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.leave_policy_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leave_policy; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.leave_policy (
    id integer DEFAULT nextval('schema_3.leave_policy_id_seq'::regclass) NOT NULL,
    leave_type character varying(50) NOT NULL,
    last_update date,
    notes text,
    total_days integer,
    intern integer,
    country character varying(50)
);


--
-- Name: leaves_applied_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.leaves_applied_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leaves_applied; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.leaves_applied (
    id integer DEFAULT nextval('schema_3.leaves_applied_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    leave_type_id integer NOT NULL,
    days numeric NOT NULL,
    start_date date NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    withdraw_action boolean DEFAULT false,
    reason text,
    approved_by integer,
    approved_date date,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    end_date date,
    docs jsonb,
    day_type character varying(20) DEFAULT 'full_day'::character varying,
    half_type character varying(20) DEFAULT NULL::character varying,
    rejection_reason text,
    rejected_at timestamp without time zone,
    CONSTRAINT chk_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: logs; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.logs (
    id integer NOT NULL,
    level text NOT NULL,
    message text NOT NULL,
    meta jsonb,
    created_at timestamp without time zone DEFAULT now()
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
-- Name: milestone_milestone_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.milestone_milestone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: milestone; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.milestone (
    milestone_id integer DEFAULT nextval('schema_3.milestone_milestone_id_seq'::regclass) NOT NULL,
    emp_id integer NOT NULL,
    milestone character varying(255) NOT NULL,
    description character varying(255),
    date date
);


--
-- Name: onboarding; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.onboarding (
    onboarding_id integer NOT NULL,
    applicant_id integer NOT NULL,
    employee_name character varying(255) NOT NULL,
    department_id integer NOT NULL,
    job_role character varying(255) NOT NULL,
    job_type character varying(50) NOT NULL,
    location character varying(255) NOT NULL,
    assigned_manager_id integer,
    assigned_manager_name character varying(255),
    joining_date date NOT NULL,
    due_date date NOT NULL,
    onboarding_status character varying(50) DEFAULT 'Not Started'::character varying NOT NULL,
    created_by integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    employee_email character varying(255) NOT NULL,
    employee_phone character varying(20),
    temporary_password character varying(255),
    welcome_message text,
    welcome_email_sent boolean DEFAULT false,
    welcome_email_sent_at timestamp without time zone,
    office_email character varying(255),
    assigned_manager_email character varying,
    email_body text,
    CONSTRAINT onboarding_job_type_check CHECK (((job_type)::text = ANY (ARRAY[('Full-Time'::character varying)::text, ('Part-Time'::character varying)::text, ('Contract'::character varying)::text, ('Intern'::character varying)::text]))),
    CONSTRAINT onboarding_onboarding_status_check CHECK (((onboarding_status)::text = ANY (ARRAY[('Not Started'::character varying)::text, ('In Progress'::character varying)::text, ('Completed'::character varying)::text])))
);


--
-- Name: onboarding_onboarding_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.onboarding_onboarding_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: onboarding_onboarding_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.onboarding_onboarding_id_seq OWNED BY schema_3.onboarding.onboarding_id;


--
-- Name: open_jobs_job_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.open_jobs_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: open_jobs; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.open_jobs (
    job_id integer DEFAULT nextval('schema_3.open_jobs_job_id_seq'::regclass) NOT NULL,
    job_title character varying(100),
    department_id integer,
    location_type character varying(50),
    job_type character varying(50),
    positions_available integer DEFAULT 1 NOT NULL,
    posting_date date,
    end_date date,
    status character varying(20) DEFAULT 'Open'::character varying,
    job_description text,
    key_responsibilities text[] DEFAULT '{}'::text[] NOT NULL,
    skills text[] DEFAULT '{}'::text[] NOT NULL,
    experience character varying(50),
    job_code character varying(20),
    salary_range integer[],
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer NOT NULL,
    updated_by integer,
    application_deadline date,
    why_join text,
    benefits jsonb DEFAULT '{}'::jsonb,
    hiring_stages jsonb DEFAULT '[]'::jsonb
);


--
-- Name: personality_test_questions; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.personality_test_questions (
    question_id integer NOT NULL,
    part character(1) NOT NULL,
    question_text text,
    option1_text text NOT NULL,
    option1_trait character varying(20) NOT NULL,
    option2_text text NOT NULL,
    option2_trait character varying(20) NOT NULL,
    option3_text text NOT NULL,
    option3_trait character varying(20) NOT NULL,
    CONSTRAINT chk_question_text CHECK ((((part = 'A'::bpchar) AND (question_text IS NULL)) OR ((part = 'B'::bpchar) AND (question_text IS NOT NULL)))),
    CONSTRAINT personality_test_questions_option1_trait_check CHECK (((option1_trait)::text = ANY (ARRAY[('O'::character varying)::text, ('C'::character varying)::text, ('E'::character varying)::text, ('A'::character varying)::text, ('N_low'::character varying)::text, ('N_high'::character varying)::text]))),
    CONSTRAINT personality_test_questions_option2_trait_check CHECK (((option2_trait)::text = ANY (ARRAY[('O'::character varying)::text, ('C'::character varying)::text, ('E'::character varying)::text, ('A'::character varying)::text, ('N_low'::character varying)::text, ('N_high'::character varying)::text]))),
    CONSTRAINT personality_test_questions_option3_trait_check CHECK (((option3_trait)::text = ANY (ARRAY[('O'::character varying)::text, ('C'::character varying)::text, ('E'::character varying)::text, ('A'::character varying)::text, ('N_low'::character varying)::text, ('N_high'::character varying)::text]))),
    CONSTRAINT personality_test_questions_part_check CHECK ((part = ANY (ARRAY['A'::bpchar, 'B'::bpchar])))
);


--
-- Name: personality_test_responses; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.personality_test_responses (
    response_id integer NOT NULL,
    test_id integer NOT NULL,
    emp_id integer NOT NULL,
    question_id integer NOT NULL,
    option1_rank character varying(10) NOT NULL,
    option2_rank character varying(10) NOT NULL,
    option3_rank character varying(10) NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT personality_test_responses_option1_rank_check CHECK (((option1_rank)::text = ANY (ARRAY[('Most'::character varying)::text, ('Neutral'::character varying)::text, ('Least'::character varying)::text]))),
    CONSTRAINT personality_test_responses_option2_rank_check CHECK (((option2_rank)::text = ANY (ARRAY[('Most'::character varying)::text, ('Neutral'::character varying)::text, ('Least'::character varying)::text]))),
    CONSTRAINT personality_test_responses_option3_rank_check CHECK (((option3_rank)::text = ANY (ARRAY[('Most'::character varying)::text, ('Neutral'::character varying)::text, ('Least'::character varying)::text])))
);


--
-- Name: personality_test_responses_response_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.personality_test_responses_response_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personality_test_responses_response_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.personality_test_responses_response_id_seq OWNED BY schema_3.personality_test_responses.response_id;


--
-- Name: personality_test_scores; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.personality_test_scores (
    score_id integer NOT NULL,
    test_id integer NOT NULL,
    emp_id integer NOT NULL,
    status character varying(10) NOT NULL,
    openness numeric(5,2),
    conscientiousness numeric(5,2),
    extraversion numeric(5,2),
    agreeableness numeric(5,2),
    neuroticism numeric(5,2),
    consistency numeric(5,2),
    CONSTRAINT personality_test_scores_agreeableness_check CHECK (((agreeableness >= (0)::numeric) AND (agreeableness <= (100)::numeric))),
    CONSTRAINT personality_test_scores_conscientiousness_check CHECK (((conscientiousness >= (0)::numeric) AND (conscientiousness <= (100)::numeric))),
    CONSTRAINT personality_test_scores_consistency_check CHECK (((consistency >= (0)::numeric) AND (consistency <= (100)::numeric))),
    CONSTRAINT personality_test_scores_extraversion_check CHECK (((extraversion >= (0)::numeric) AND (extraversion <= (100)::numeric))),
    CONSTRAINT personality_test_scores_neuroticism_check CHECK (((neuroticism >= (0)::numeric) AND (neuroticism <= (100)::numeric))),
    CONSTRAINT personality_test_scores_openness_check CHECK (((openness >= (0)::numeric) AND (openness <= (100)::numeric))),
    CONSTRAINT personality_test_scores_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('completed'::character varying)::text])))
);


--
-- Name: personality_test_scores_score_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.personality_test_scores_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personality_test_scores_score_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.personality_test_scores_score_id_seq OWNED BY schema_3.personality_test_scores.score_id;


--
-- Name: project_departments_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.project_departments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_departments; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.project_departments (
    department_id integer DEFAULT nextval('schema_3.project_departments_id_seq'::regclass) NOT NULL,
    department text,
    manager_id integer,
    department_code character varying(25),
    created_by integer NOT NULL,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'active'::character varying
);


--
-- Name: resume_bank; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.resume_bank (
    resume_bank_id integer NOT NULL,
    applicant_name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(20),
    date_of_birth date,
    gender character varying(20),
    address text,
    city character varying(100),
    country character varying(100),
    experience character varying(50),
    highest_educational_qualification text,
    portfolio_link text,
    application_id character varying(100),
    job_id integer,
    job_type character varying(50),
    application_date date NOT NULL,
    preferred_joining_date date,
    referral_emp_id integer,
    dept_id integer,
    documents jsonb DEFAULT '{}'::jsonb,
    rejected_reason character varying(255) NOT NULL,
    rejection_source character varying(50) NOT NULL,
    rejection_detail text,
    rejected_by integer,
    rejected_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(50) DEFAULT 'Available'::character varying,
    moved_to_applicant_id integer,
    moved_to_applicant_date timestamp without time zone,
    moved_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_by integer,
    CONSTRAINT chk_email_format CHECK (((email)::text ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'::text)),
    CONSTRAINT chk_rejection_source CHECK (((rejection_source)::text = ANY (ARRAY[('applicant'::character varying)::text, ('referral'::character varying)::text, ('interview'::character varying)::text]))),
    CONSTRAINT chk_status CHECK (((status)::text = ANY (ARRAY[('Available'::character varying)::text, ('Moved to Applicant'::character varying)::text, ('Archived'::character varying)::text])))
);


--
-- Name: resume_bank_resume_bank_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.resume_bank_resume_bank_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: resume_bank_resume_bank_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_3; Owner: -
--

ALTER SEQUENCE schema_3.resume_bank_resume_bank_id_seq OWNED BY schema_3.resume_bank.resume_bank_id;


--
-- Name: sub_department_id_seq; Type: SEQUENCE; Schema: schema_3; Owner: -
--

CREATE SEQUENCE schema_3.sub_department_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sub_department; Type: TABLE; Schema: schema_3; Owner: -
--

CREATE TABLE schema_3.sub_department (
    subdepartment_id integer DEFAULT nextval('schema_3.sub_department_id_seq'::regclass) NOT NULL,
    department_id integer,
    manager_id integer,
    subdepartment_name character varying(255),
    subdepartment_code character varying(30),
    sharepoint_site_name character varying(255),
    sharepoint_site_id character varying(300),
    created_by integer NOT NULL,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'active'::character varying,
    CONSTRAINT chk_sub_department_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
);


--
-- Name: company_property property_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.company_property ALTER COLUMN property_id SET DEFAULT nextval('schema_3.company_property_property_id_seq'::regclass);


--
-- Name: employee_offboarding offboarding_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_offboarding ALTER COLUMN offboarding_id SET DEFAULT nextval('schema_3.employee_offboarding_offboarding_id_seq'::regclass);


--
-- Name: employee_referrals referral_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_referrals ALTER COLUMN referral_id SET DEFAULT nextval('schema_3.employee_referrals_referral_id_seq1'::regclass);


--
-- Name: employee_roles id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_roles ALTER COLUMN id SET DEFAULT nextval('schema_3.employee_roles_id_seq'::regclass);


--
-- Name: employee_tests test_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_tests ALTER COLUMN test_id SET DEFAULT nextval('schema_3.employee_tests_test_id_seq'::regclass);


--
-- Name: exit_feedback feedback_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.exit_feedback ALTER COLUMN feedback_id SET DEFAULT nextval('schema_3.exit_feedback_feedback_id_seq'::regclass);


--
-- Name: interviews interview_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.interviews ALTER COLUMN interview_id SET DEFAULT nextval('schema_3.interviews_interview_id_seq1'::regclass);


--
-- Name: job_requests request_job_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_requests ALTER COLUMN request_job_id SET DEFAULT nextval('schema_3.job_requests_request_job_id_seq'::regclass);


--
-- Name: job_title job_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_title ALTER COLUMN job_id SET DEFAULT nextval('schema_3.job_title_job_id_seq'::regclass);


--
-- Name: logs id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.logs ALTER COLUMN id SET DEFAULT nextval('schema_3.logs_id_seq'::regclass);


--
-- Name: onboarding onboarding_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.onboarding ALTER COLUMN onboarding_id SET DEFAULT nextval('schema_3.onboarding_onboarding_id_seq'::regclass);


--
-- Name: personality_test_responses response_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_responses ALTER COLUMN response_id SET DEFAULT nextval('schema_3.personality_test_responses_response_id_seq'::regclass);


--
-- Name: personality_test_scores score_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_scores ALTER COLUMN score_id SET DEFAULT nextval('schema_3.personality_test_scores_score_id_seq'::regclass);


--
-- Name: resume_bank resume_bank_id; Type: DEFAULT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank ALTER COLUMN resume_bank_id SET DEFAULT nextval('schema_3.resume_bank_resume_bank_id_seq'::regclass);


--
-- Name: applicants applicants_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.applicants
    ADD CONSTRAINT applicants_pkey PRIMARY KEY (applicant_id);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (asset_id);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (cer_id);


--
-- Name: company_property company_property_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.company_property
    ADD CONSTRAINT company_property_pkey PRIMARY KEY (property_id);


--
-- Name: company_property company_property_property_id_code_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.company_property
    ADD CONSTRAINT company_property_property_id_code_key UNIQUE (property_id_code);


--
-- Name: employee_bank_details employee_bank_details_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_bank_details
    ADD CONSTRAINT employee_bank_details_pkey PRIMARY KEY (id);


--
-- Name: employee_contacts employee_contacts_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_contacts
    ADD CONSTRAINT employee_contacts_pkey PRIMARY KEY (id);


--
-- Name: employee_offboarding employee_offboarding_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_offboarding
    ADD CONSTRAINT employee_offboarding_pkey PRIMARY KEY (offboarding_id);


--
-- Name: employee_referrals employee_referrals_application_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_referrals
    ADD CONSTRAINT employee_referrals_application_id_key UNIQUE (application_id);


--
-- Name: employee_referrals employee_referrals_pkey_1; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_referrals
    ADD CONSTRAINT employee_referrals_pkey_1 PRIMARY KEY (referral_id);


--
-- Name: employee_roles employee_roles_emp_id_role_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_roles
    ADD CONSTRAINT employee_roles_emp_id_role_id_key UNIQUE (emp_id, role_id);


--
-- Name: employee_roles employee_roles_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_roles
    ADD CONSTRAINT employee_roles_pkey PRIMARY KEY (id);


--
-- Name: employee_test_question_order employee_test_question_order_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_question_order
    ADD CONSTRAINT employee_test_question_order_pkey PRIMARY KEY (test_id, emp_id, order_no);


--
-- Name: employee_test_sessions employee_test_sessions_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_sessions
    ADD CONSTRAINT employee_test_sessions_pkey PRIMARY KEY (test_id, emp_id);


--
-- Name: employee_tests employee_tests_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_tests
    ADD CONSTRAINT employee_tests_pkey PRIMARY KEY (test_id);


--
-- Name: exit_feedback exit_feedback_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.exit_feedback
    ADD CONSTRAINT exit_feedback_pkey PRIMARY KEY (feedback_id);


--
-- Name: holidays holidays_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.holidays
    ADD CONSTRAINT holidays_pkey PRIMARY KEY (id);


--
-- Name: hrm_employees hrm_employees_auth_id_key; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.hrm_employees
    ADD CONSTRAINT hrm_employees_auth_id_key UNIQUE (auth_id);


--
-- Name: hrm_employees hrm_employees_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.hrm_employees
    ADD CONSTRAINT hrm_employees_pkey PRIMARY KEY (emp_id);


--
-- Name: interviews interviews_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.interviews
    ADD CONSTRAINT interviews_pkey PRIMARY KEY (interview_id);


--
-- Name: job_history job_history_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_history
    ADD CONSTRAINT job_history_pkey PRIMARY KEY (job_id);


--
-- Name: job_requests job_requests_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_requests
    ADD CONSTRAINT job_requests_pkey PRIMARY KEY (request_job_id);


--
-- Name: job_title job_title_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_title
    ADD CONSTRAINT job_title_pkey PRIMARY KEY (job_id);


--
-- Name: leave_policy leave_policy_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.leave_policy
    ADD CONSTRAINT leave_policy_pkey PRIMARY KEY (id);


--
-- Name: leaves_applied leaves_applied_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.leaves_applied
    ADD CONSTRAINT leaves_applied_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: milestone milestone_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.milestone
    ADD CONSTRAINT milestone_pkey PRIMARY KEY (milestone_id);


--
-- Name: onboarding onboarding_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.onboarding
    ADD CONSTRAINT onboarding_pkey PRIMARY KEY (onboarding_id);


--
-- Name: open_jobs open_jobs_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.open_jobs
    ADD CONSTRAINT open_jobs_pkey PRIMARY KEY (job_id);


--
-- Name: personality_test_questions personality_test_questions_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_questions
    ADD CONSTRAINT personality_test_questions_pkey PRIMARY KEY (question_id);


--
-- Name: personality_test_responses personality_test_responses_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_responses
    ADD CONSTRAINT personality_test_responses_pkey PRIMARY KEY (response_id);


--
-- Name: personality_test_scores personality_test_scores_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_scores
    ADD CONSTRAINT personality_test_scores_pkey PRIMARY KEY (score_id);


--
-- Name: project_departments project_departments_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_departments
    ADD CONSTRAINT project_departments_pkey PRIMARY KEY (department_id);


--
-- Name: resume_bank resume_bank_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT resume_bank_pkey PRIMARY KEY (resume_bank_id);


--
-- Name: sub_department sub_department_pkey; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sub_department
    ADD CONSTRAINT sub_department_pkey PRIMARY KEY (subdepartment_id);


--
-- Name: onboarding uq_applicant_onboarding; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.onboarding
    ADD CONSTRAINT uq_applicant_onboarding UNIQUE (applicant_id);


--
-- Name: hrm_employees uq_hrm_employees_crm_id; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.hrm_employees
    ADD CONSTRAINT uq_hrm_employees_crm_id UNIQUE (crm_id);


--
-- Name: sub_department uq_sub_department; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sub_department
    ADD CONSTRAINT uq_sub_department UNIQUE (department_id, subdepartment_name);


--
-- Name: employee_test_question_order uq_test_emp_question; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_question_order
    ADD CONSTRAINT uq_test_emp_question UNIQUE (test_id, emp_id, question_id);


--
-- Name: personality_test_responses uq_test_emp_question_response; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_responses
    ADD CONSTRAINT uq_test_emp_question_response UNIQUE (test_id, emp_id, question_id);


--
-- Name: personality_test_scores uq_test_emp_score; Type: CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_scores
    ADD CONSTRAINT uq_test_emp_score UNIQUE (test_id, emp_id);


--
-- Name: idx_applicants_application_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_application_date ON schema_3.applicants USING btree (application_date);


--
-- Name: idx_applicants_dept_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_dept_id ON schema_3.applicants USING btree (dept_id);


--
-- Name: idx_applicants_documents; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_documents ON schema_3.applicants USING gin (documents);


--
-- Name: idx_applicants_email; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_email ON schema_3.applicants USING btree (email);


--
-- Name: idx_applicants_job_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_job_id ON schema_3.applicants USING btree (job_id);


--
-- Name: idx_applicants_next_interview; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_next_interview ON schema_3.applicants USING btree (next_interview);


--
-- Name: idx_applicants_referral_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_referral_emp ON schema_3.applicants USING btree (referral_emp_id);


--
-- Name: idx_applicants_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_applicants_status ON schema_3.applicants USING btree (application_status);


--
-- Name: idx_company_property_emp_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_company_property_emp_id ON schema_3.company_property USING btree (emp_id);


--
-- Name: idx_company_property_issue_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_company_property_issue_date ON schema_3.company_property USING btree (issue_date);


--
-- Name: idx_company_property_type; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_company_property_type ON schema_3.company_property USING btree (property_type);


--
-- Name: idx_employee_bank_details_emp_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_bank_details_emp_id ON schema_3.employee_bank_details USING btree (emp_id);


--
-- Name: idx_employee_referrals_candidate_email_1; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_referrals_candidate_email_1 ON schema_3.employee_referrals USING btree (candidate_email);


--
-- Name: idx_employee_referrals_date_1; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_referrals_date_1 ON schema_3.employee_referrals USING btree (referral_date);


--
-- Name: idx_employee_referrals_emp_id_1; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_referrals_emp_id_1 ON schema_3.employee_referrals USING btree (referring_emp_id);


--
-- Name: idx_employee_referrals_job_id_1; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_referrals_job_id_1 ON schema_3.employee_referrals USING btree (job_id);


--
-- Name: idx_employee_referrals_status_1; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_referrals_status_1 ON schema_3.employee_referrals USING btree (referral_status);


--
-- Name: idx_employee_roles_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_roles_emp ON schema_3.employee_roles USING btree (emp_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_employee_test_sessions_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_test_sessions_emp ON schema_3.employee_test_sessions USING btree (emp_id);


--
-- Name: idx_employee_test_sessions_emp_started; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_test_sessions_emp_started ON schema_3.employee_test_sessions USING btree (emp_id, started_at DESC);


--
-- Name: idx_employee_test_sessions_started_at; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_test_sessions_started_at ON schema_3.employee_test_sessions USING btree (started_at);


--
-- Name: idx_employee_test_sessions_status_started; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_employee_test_sessions_status_started ON schema_3.employee_test_sessions USING btree (status, started_at DESC);


--
-- Name: idx_exit_feedback_offboarding; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_exit_feedback_offboarding ON schema_3.exit_feedback USING btree (offboarding_id);


--
-- Name: idx_hrm_employees_languages; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_hrm_employees_languages ON schema_3.hrm_employees USING gin (languages);


--
-- Name: idx_interview_applicant_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_applicant_id ON schema_3.interviews USING btree (applicant_id);


--
-- Name: idx_interview_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_date ON schema_3.interviews USING btree (meeting_date);


--
-- Name: idx_interview_feedback; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_feedback ON schema_3.interviews USING gin (feedback);


--
-- Name: idx_interview_job_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_job_id ON schema_3.interviews USING btree (job_id);


--
-- Name: idx_interview_scheduled_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_scheduled_by ON schema_3.interviews USING btree (scheduled_by);


--
-- Name: idx_interview_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_interview_status ON schema_3.interviews USING btree (status);


--
-- Name: idx_job_positions_department; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_positions_department ON schema_3.open_jobs USING btree (department_id);


--
-- Name: idx_job_positions_posting_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_positions_posting_date ON schema_3.open_jobs USING btree (posting_date);


--
-- Name: idx_job_positions_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_positions_status ON schema_3.open_jobs USING btree (status);


--
-- Name: idx_job_requests_department; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_requests_department ON schema_3.job_requests USING btree (department_id);


--
-- Name: idx_job_requests_priority; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_requests_priority ON schema_3.job_requests USING btree (priority);


--
-- Name: idx_job_requests_requested_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_requests_requested_by ON schema_3.job_requests USING btree (requested_by_id);


--
-- Name: idx_job_requests_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_requests_status ON schema_3.job_requests USING btree (status);


--
-- Name: idx_job_title_created_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_title_created_by ON schema_3.job_title USING btree (created_by);


--
-- Name: idx_job_title_title; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_job_title_title ON schema_3.job_title USING btree (job_title);


--
-- Name: idx_offboarding_created_at; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_offboarding_created_at ON schema_3.employee_offboarding USING btree (created_at);


--
-- Name: idx_offboarding_department; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_offboarding_department ON schema_3.employee_offboarding USING btree (department_id);


--
-- Name: idx_offboarding_employee; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_offboarding_employee ON schema_3.employee_offboarding USING btree (emp_id);


--
-- Name: idx_offboarding_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_offboarding_manager ON schema_3.employee_offboarding USING btree (manager_id);


--
-- Name: idx_offboarding_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_offboarding_status ON schema_3.employee_offboarding USING btree (status);


--
-- Name: idx_onboarding_applicant; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_applicant ON schema_3.onboarding USING btree (applicant_id);


--
-- Name: idx_onboarding_department_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_department_id ON schema_3.onboarding USING btree (department_id);


--
-- Name: idx_onboarding_due_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_due_date ON schema_3.onboarding USING btree (due_date);


--
-- Name: idx_onboarding_joining_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_joining_date ON schema_3.onboarding USING btree (joining_date);


--
-- Name: idx_onboarding_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_manager ON schema_3.onboarding USING btree (assigned_manager_id);


--
-- Name: idx_onboarding_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_onboarding_status ON schema_3.onboarding USING btree (onboarding_status);


--
-- Name: idx_project_departments_created_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_project_departments_created_by ON schema_3.project_departments USING btree (created_by);


--
-- Name: idx_project_departments_department_code; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_project_departments_department_code ON schema_3.project_departments USING btree (department_code);


--
-- Name: idx_project_departments_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_project_departments_manager ON schema_3.project_departments USING btree (manager_id);


--
-- Name: idx_question_order_lookup; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_question_order_lookup ON schema_3.employee_test_question_order USING btree (question_id);


--
-- Name: idx_responses_created_at; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_responses_created_at ON schema_3.personality_test_responses USING btree (created_at DESC);


--
-- Name: idx_responses_question; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_responses_question ON schema_3.personality_test_responses USING btree (question_id);


--
-- Name: idx_responses_test_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_responses_test_emp ON schema_3.personality_test_responses USING btree (test_id, emp_id);


--
-- Name: idx_resume_bank_applicant_name; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_applicant_name ON schema_3.resume_bank USING btree (applicant_name);


--
-- Name: idx_resume_bank_application_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_application_date ON schema_3.resume_bank USING btree (application_date);


--
-- Name: idx_resume_bank_created_at; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_created_at ON schema_3.resume_bank USING btree (created_at);


--
-- Name: idx_resume_bank_email; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_email ON schema_3.resume_bank USING btree (email);


--
-- Name: idx_resume_bank_experience; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_experience ON schema_3.resume_bank USING btree (experience);


--
-- Name: idx_resume_bank_job_experience; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_job_experience ON schema_3.resume_bank USING btree (job_id, experience);


--
-- Name: idx_resume_bank_job_id; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_job_id ON schema_3.resume_bank USING btree (job_id);


--
-- Name: idx_resume_bank_rejected_date; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_rejected_date ON schema_3.resume_bank USING btree (rejected_date);


--
-- Name: idx_resume_bank_rejected_reason; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_rejected_reason ON schema_3.resume_bank USING btree (rejected_reason);


--
-- Name: idx_resume_bank_rejection_source; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_rejection_source ON schema_3.resume_bank USING btree (rejection_source);


--
-- Name: idx_resume_bank_rejection_source_reason; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_rejection_source_reason ON schema_3.resume_bank USING btree (rejection_source, rejected_reason);


--
-- Name: idx_resume_bank_search; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_search ON schema_3.resume_bank USING gin (to_tsvector('english'::regconfig, (COALESCE(applicant_name, ''::character varying))::text));


--
-- Name: idx_resume_bank_status; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_status ON schema_3.resume_bank USING btree (status);


--
-- Name: idx_resume_bank_status_job; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_resume_bank_status_job ON schema_3.resume_bank USING btree (status, job_id);


--
-- Name: idx_resume_bank_unique_candidate; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE UNIQUE INDEX idx_resume_bank_unique_candidate ON schema_3.resume_bank USING btree (email, job_id) WHERE ((status)::text <> 'Archived'::text);


--
-- Name: idx_scores_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_scores_emp ON schema_3.personality_test_scores USING btree (emp_id);


--
-- Name: idx_scores_test_emp; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_scores_test_emp ON schema_3.personality_test_scores USING btree (test_id, emp_id);


--
-- Name: idx_sub_department_code; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sub_department_code ON schema_3.sub_department USING btree (subdepartment_code);


--
-- Name: idx_sub_department_created_by; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sub_department_created_by ON schema_3.sub_department USING btree (created_by);


--
-- Name: idx_sub_department_department; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sub_department_department ON schema_3.sub_department USING btree (department_id);


--
-- Name: idx_sub_department_manager; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_sub_department_manager ON schema_3.sub_department USING btree (manager_id);


--
-- Name: idx_test_emp_order; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_test_emp_order ON schema_3.employee_test_question_order USING btree (test_id, emp_id, order_no);


--
-- Name: idx_tests_emp_status_started; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE INDEX idx_tests_emp_status_started ON schema_3.employee_test_sessions USING btree (emp_id, status, started_at DESC);


--
-- Name: uq_job_title_dept; Type: INDEX; Schema: schema_3; Owner: -
--

CREATE UNIQUE INDEX uq_job_title_dept ON schema_3.job_title USING btree (department_id, job_title);


--
-- Name: interviews interview_timestamps_trigger; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER interview_timestamps_trigger BEFORE INSERT OR UPDATE ON schema_3.interviews FOR EACH ROW EXECUTE FUNCTION schema_3.update_interview_timestamps();


--
-- Name: sub_department trg_sync_scope_on_subdept_move; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trg_sync_scope_on_subdept_move AFTER UPDATE OF department_id ON schema_3.sub_department FOR EACH ROW EXECUTE FUNCTION schema_3.sync_scope_on_subdept_move();


--
-- Name: employee_test_sessions trg_test_status_enforce; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trg_test_status_enforce BEFORE UPDATE ON schema_3.employee_test_sessions FOR EACH ROW EXECUTE FUNCTION schema_3.trg_enforce_test_status();


--
-- Name: applicants trigger_generate_application_id; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_generate_application_id BEFORE INSERT ON schema_3.applicants FOR EACH ROW EXECUTE FUNCTION schema_3.generate_application_id();


--
-- Name: resume_bank trigger_resume_bank_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_resume_bank_updated_at BEFORE UPDATE ON schema_3.resume_bank FOR EACH ROW EXECUTE FUNCTION public.update_resume_bank_updated_at();


--
-- Name: resume_bank trigger_update_move_status; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER trigger_update_move_status BEFORE UPDATE ON schema_3.resume_bank FOR EACH ROW EXECUTE FUNCTION public.update_move_status();


--
-- Name: applicants update_applicants_modtime; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_applicants_modtime BEFORE UPDATE ON schema_3.applicants FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: employee_offboarding update_employee_offboarding_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_employee_offboarding_updated_at BEFORE UPDATE ON schema_3.employee_offboarding FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: exit_feedback update_exit_feedback_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_exit_feedback_updated_at BEFORE UPDATE ON schema_3.exit_feedback FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: open_jobs update_job_positions_modtime; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_job_positions_modtime BEFORE UPDATE ON schema_3.open_jobs FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- Name: job_requests update_job_requests_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_job_requests_updated_at BEFORE UPDATE ON schema_3.job_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: open_jobs update_open_jobs_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_open_jobs_updated_at BEFORE UPDATE ON schema_3.open_jobs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: project_departments update_project_departments_updated_at; Type: TRIGGER; Schema: schema_3; Owner: -
--

CREATE TRIGGER update_project_departments_updated_at BEFORE UPDATE ON schema_3.project_departments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: assets assets_emp_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.assets
    ADD CONSTRAINT assets_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: certificates certificates_emp_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.certificates
    ADD CONSTRAINT certificates_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: employee_roles employee_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_roles
    ADD CONSTRAINT employee_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.user_roles(id);


--
-- Name: employee_test_question_order employee_test_question_order_question_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_question_order
    ADD CONSTRAINT employee_test_question_order_question_id_fkey FOREIGN KEY (question_id) REFERENCES schema_3.personality_test_questions(question_id) ON DELETE CASCADE;


--
-- Name: employee_test_question_order employee_test_question_order_test_id_emp_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_question_order
    ADD CONSTRAINT employee_test_question_order_test_id_emp_id_fkey FOREIGN KEY (test_id, emp_id) REFERENCES schema_3.employee_test_sessions(test_id, emp_id) ON DELETE CASCADE;


--
-- Name: employee_test_sessions employee_test_sessions_test_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_test_sessions
    ADD CONSTRAINT employee_test_sessions_test_id_fkey FOREIGN KEY (test_id) REFERENCES schema_3.employee_tests(test_id) ON DELETE CASCADE;


--
-- Name: applicants fk_applicants_job_id; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.applicants
    ADD CONSTRAINT fk_applicants_job_id FOREIGN KEY (job_id) REFERENCES schema_3.open_jobs(job_id);


--
-- Name: applicants fk_applicants_referral_emp; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.applicants
    ADD CONSTRAINT fk_applicants_referral_emp FOREIGN KEY (referral_emp_id) REFERENCES schema_3.hrm_employees(emp_id);


--
-- Name: leaves_applied fk_approver; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.leaves_applied
    ADD CONSTRAINT fk_approver FOREIGN KEY (approved_by) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: company_property fk_emp_id; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.company_property
    ADD CONSTRAINT fk_emp_id FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: employee_bank_details fk_employee; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_bank_details
    ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: employee_contacts fk_employee; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_contacts
    ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: leaves_applied fk_employee; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.leaves_applied
    ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: exit_feedback fk_feedback_offboarding; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.exit_feedback
    ADD CONSTRAINT fk_feedback_offboarding FOREIGN KEY (offboarding_id) REFERENCES schema_118.employee_offboarding(offboarding_id) ON DELETE CASCADE;


--
-- Name: interviews fk_interview_applicant; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.interviews
    ADD CONSTRAINT fk_interview_applicant FOREIGN KEY (applicant_id) REFERENCES schema_3.applicants(applicant_id) ON DELETE CASCADE;


--
-- Name: interviews fk_interview_job; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.interviews
    ADD CONSTRAINT fk_interview_job FOREIGN KEY (job_id) REFERENCES schema_3.open_jobs(job_id) ON DELETE CASCADE;


--
-- Name: job_requests fk_job_requests_requested_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_requests
    ADD CONSTRAINT fk_job_requests_requested_by FOREIGN KEY (requested_by_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: job_title fk_job_title_department; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_title
    ADD CONSTRAINT fk_job_title_department FOREIGN KEY (department_id) REFERENCES schema_3.project_departments(department_id) ON DELETE CASCADE;


--
-- Name: job_title fk_job_title_sub_department; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_title
    ADD CONSTRAINT fk_job_title_sub_department FOREIGN KEY (subdepartment_id) REFERENCES schema_3.sub_department(subdepartment_id) ON DELETE SET NULL;


--
-- Name: job_title fk_job_title_subdepartment; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_title
    ADD CONSTRAINT fk_job_title_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES schema_3.sub_department(subdepartment_id) ON DELETE SET NULL;


--
-- Name: leaves_applied fk_leave_policy; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.leaves_applied
    ADD CONSTRAINT fk_leave_policy FOREIGN KEY (leave_type_id) REFERENCES schema_3.leave_policy(id) ON DELETE RESTRICT;


--
-- Name: employee_offboarding fk_offboarding_employee; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_offboarding
    ADD CONSTRAINT fk_offboarding_employee FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: employee_offboarding fk_offboarding_manager; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.employee_offboarding
    ADD CONSTRAINT fk_offboarding_manager FOREIGN KEY (manager_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: project_departments fk_project_departments_manager_crm; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.project_departments
    ADD CONSTRAINT fk_project_departments_manager_crm FOREIGN KEY (manager_id) REFERENCES schema_3.hrm_employees(crm_id) ON DELETE SET NULL;


--
-- Name: sub_department fk_project_sub_department_department; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sub_department
    ADD CONSTRAINT fk_project_sub_department_department FOREIGN KEY (department_id) REFERENCES schema_3.project_departments(department_id) ON DELETE CASCADE;


--
-- Name: sub_department fk_project_sub_department_manager; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.sub_department
    ADD CONSTRAINT fk_project_sub_department_manager FOREIGN KEY (manager_id) REFERENCES schema_3.hrm_employees(crm_id) ON DELETE SET NULL;


--
-- Name: personality_test_responses fk_responses_sessions; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_responses
    ADD CONSTRAINT fk_responses_sessions FOREIGN KEY (test_id, emp_id) REFERENCES schema_3.employee_test_sessions(test_id, emp_id) ON DELETE CASCADE;


--
-- Name: resume_bank fk_resume_bank_created_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_created_by FOREIGN KEY (created_by) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_job; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_job FOREIGN KEY (job_id) REFERENCES schema_3.open_jobs(job_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_moved_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_moved_by FOREIGN KEY (moved_by) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_moved_to_applicant; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_moved_to_applicant FOREIGN KEY (moved_to_applicant_id) REFERENCES schema_3.applicants(applicant_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_referral_emp; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_referral_emp FOREIGN KEY (referral_emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_rejected_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_rejected_by FOREIGN KEY (rejected_by) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: resume_bank fk_resume_bank_updated_by; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.resume_bank
    ADD CONSTRAINT fk_resume_bank_updated_by FOREIGN KEY (updated_by) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE SET NULL;


--
-- Name: personality_test_scores fk_scores_sessions; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_scores
    ADD CONSTRAINT fk_scores_sessions FOREIGN KEY (test_id, emp_id) REFERENCES schema_3.employee_test_sessions(test_id, emp_id) ON DELETE CASCADE;


--
-- Name: hrm_employees fk_user_roles; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.hrm_employees
    ADD CONSTRAINT fk_user_roles FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id);


--
-- Name: hrm_employees hrm_employees_auth_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.hrm_employees
    ADD CONSTRAINT hrm_employees_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id);


--
-- Name: job_history job_history_emp_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.job_history
    ADD CONSTRAINT job_history_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: milestone milestone_emp_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.milestone
    ADD CONSTRAINT milestone_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_3.hrm_employees(emp_id) ON DELETE CASCADE;


--
-- Name: personality_test_responses personality_test_responses_question_id_fkey; Type: FK CONSTRAINT; Schema: schema_3; Owner: -
--

ALTER TABLE ONLY schema_3.personality_test_responses
    ADD CONSTRAINT personality_test_responses_question_id_fkey FOREIGN KEY (question_id) REFERENCES schema_3.personality_test_questions(question_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict gr2dygaSJmMznZYtKYiqjrp1PZBAZD5a9qgoFE8xDPI8Vif11nAnGTcd83mJPbY

