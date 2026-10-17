--
-- PostgreSQL database dump
--

\restrict 0NiEJYl0WpQRKVgPNYZgGNhb8M5zEKuY5TRH1b7tDuJIqrYvV0C5GDZbafGl6j8

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
-- Name: update_employee_referrals_timestamps(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_employee_referrals_timestamps() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF TG_OP = 'INSERT' THEN NEW.created_at = now(); NEW.updated_at = now(); ELSIF TG_OP = 'UPDATE' THEN NEW.updated_at = now(); END IF; RETURN NEW; END; $$;


--
-- Name: update_modified_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_modified_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;


--
-- Name: update_move_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_move_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.moved_to_applicant_id IS NULL AND NEW.moved_to_applicant_id IS NOT NULL THEN
        NEW.status = 'Moved to Applicant';
        NEW.moved_to_applicant_date = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: update_resume_bank_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_resume_bank_updated_at() RETURNS trigger
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
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: holidays_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.holidays_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.holidays (
    id integer DEFAULT nextval('public.holidays_id_seq'::regclass) NOT NULL,
    holiday_name character varying(100) NOT NULL,
    holiday_date date NOT NULL,
    holiday_type character varying(50),
    country character varying(50)
);


--
-- Name: hrm_auth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_auth (
    auth_id integer NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    tenent_id integer NOT NULL,
    is_active boolean DEFAULT true,
    email_verified boolean DEFAULT false,
    last_login_at timestamp without time zone,
    password_changed_at timestamp without time zone,
    failed_login_attempts integer DEFAULT 0,
    locked_until timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: hrm_auth_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_auth_audit_log (
    log_id integer NOT NULL,
    auth_id integer,
    event_type character varying(50),
    ip_address character varying(45),
    user_agent text,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: hrm_auth_audit_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hrm_auth_audit_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hrm_auth_audit_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hrm_auth_audit_log_log_id_seq OWNED BY public.hrm_auth_audit_log.log_id;


--
-- Name: hrm_auth_auth_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hrm_auth_auth_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hrm_auth_auth_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hrm_auth_auth_id_seq OWNED BY public.hrm_auth.auth_id;


--
-- Name: hrm_auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_auth_sessions (
    session_id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_id integer NOT NULL,
    access_token_hash character varying(255) NOT NULL,
    refresh_token_id uuid,
    ip_address character varying(45),
    user_agent text,
    expires_at timestamp without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    last_activity_at timestamp without time zone DEFAULT now()
);


--
-- Name: hrm_password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_password_reset_tokens (
    reset_id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_id integer NOT NULL,
    token_hash character varying(255) NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    used_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: hrm_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_permissions (
    permission_id integer NOT NULL,
    key character varying(100) NOT NULL,
    module character varying(50) NOT NULL,
    submodule character varying(50) DEFAULT NULL::character varying,
    action character varying(50) NOT NULL,
    label character varying(100),
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    submodule_label text
);


--
-- Name: hrm_permissions_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hrm_permissions_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hrm_permissions_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hrm_permissions_permission_id_seq OWNED BY public.hrm_permissions.permission_id;


--
-- Name: hrm_refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hrm_refresh_tokens (
    token_id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_id integer NOT NULL,
    token_hash character varying(255) NOT NULL,
    device_info jsonb,
    expires_at timestamp without time zone NOT NULL,
    revoked_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    ip_address character varying(45),
    user_agent text,
    last_used_at timestamp without time zone DEFAULT now()
);


--
-- Name: logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logs (
    id integer NOT NULL,
    level character varying(50) NOT NULL,
    message text NOT NULL,
    meta jsonb
);


--
-- Name: logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.logs_id_seq OWNED BY public.logs.id;


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id integer NOT NULL,
    role character varying(50) NOT NULL,
    description text,
    is_system boolean DEFAULT false,
    parent_role_id integer,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_base boolean DEFAULT false,
    privilege_level integer DEFAULT 10 NOT NULL
);


--
-- Name: user_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_roles_id_seq OWNED BY public.user_roles.id;


--
-- Name: hrm_auth auth_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth ALTER COLUMN auth_id SET DEFAULT nextval('public.hrm_auth_auth_id_seq'::regclass);


--
-- Name: hrm_auth_audit_log log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_audit_log ALTER COLUMN log_id SET DEFAULT nextval('public.hrm_auth_audit_log_log_id_seq'::regclass);


--
-- Name: hrm_permissions permission_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_permissions ALTER COLUMN permission_id SET DEFAULT nextval('public.hrm_permissions_permission_id_seq'::regclass);


--
-- Name: logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs ALTER COLUMN id SET DEFAULT nextval('public.logs_id_seq'::regclass);


--
-- Name: user_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles ALTER COLUMN id SET DEFAULT nextval('public.user_roles_id_seq'::regclass);


--
-- Name: hrm_auth_audit_log hrm_auth_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_audit_log
    ADD CONSTRAINT hrm_auth_audit_log_pkey PRIMARY KEY (log_id);


--
-- Name: hrm_auth hrm_auth_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth
    ADD CONSTRAINT hrm_auth_email_key UNIQUE (email);


--
-- Name: hrm_auth hrm_auth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth
    ADD CONSTRAINT hrm_auth_pkey PRIMARY KEY (auth_id);


--
-- Name: hrm_auth_sessions hrm_auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_sessions
    ADD CONSTRAINT hrm_auth_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: hrm_password_reset_tokens hrm_password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_password_reset_tokens
    ADD CONSTRAINT hrm_password_reset_tokens_pkey PRIMARY KEY (reset_id);


--
-- Name: hrm_permissions hrm_permissions_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_permissions
    ADD CONSTRAINT hrm_permissions_key_key UNIQUE (key);


--
-- Name: hrm_permissions hrm_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_permissions
    ADD CONSTRAINT hrm_permissions_pkey PRIMARY KEY (permission_id);


--
-- Name: hrm_refresh_tokens hrm_refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_refresh_tokens
    ADD CONSTRAINT hrm_refresh_tokens_pkey PRIMARY KEY (token_id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_role_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_key UNIQUE (role);


--
-- Name: idx_audit_log_auth_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_auth_id ON public.hrm_auth_audit_log USING btree (auth_id);


--
-- Name: idx_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_created_at ON public.hrm_auth_audit_log USING btree (created_at);


--
-- Name: idx_audit_log_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_event_type ON public.hrm_auth_audit_log USING btree (event_type);


--
-- Name: idx_auth_sessions_auth_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_auth_id ON public.hrm_auth_sessions USING btree (auth_id);


--
-- Name: idx_auth_sessions_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_expires_at ON public.hrm_auth_sessions USING btree (expires_at);


--
-- Name: idx_password_reset_auth_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_password_reset_auth_id ON public.hrm_password_reset_tokens USING btree (auth_id);


--
-- Name: idx_password_reset_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_password_reset_expires ON public.hrm_password_reset_tokens USING btree (expires_at);


--
-- Name: idx_refresh_tokens_auth_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_tokens_auth_id ON public.hrm_refresh_tokens USING btree (auth_id);


--
-- Name: idx_refresh_tokens_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_tokens_expires_at ON public.hrm_refresh_tokens USING btree (expires_at);


--
-- Name: idx_refresh_tokens_last_used_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_tokens_last_used_at ON public.hrm_refresh_tokens USING btree (last_used_at);


--
-- Name: idx_refresh_tokens_revoked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_tokens_revoked_at ON public.hrm_refresh_tokens USING btree (revoked_at);


--
-- Name: hrm_password_reset_tokens fk_password_reset_auth; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_password_reset_tokens
    ADD CONSTRAINT fk_password_reset_auth FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id) ON DELETE CASCADE;


--
-- Name: hrm_auth_audit_log hrm_auth_audit_log_auth_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_audit_log
    ADD CONSTRAINT hrm_auth_audit_log_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id);


--
-- Name: hrm_auth_sessions hrm_auth_sessions_auth_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_sessions
    ADD CONSTRAINT hrm_auth_sessions_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id);


--
-- Name: hrm_auth_sessions hrm_auth_sessions_refresh_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_auth_sessions
    ADD CONSTRAINT hrm_auth_sessions_refresh_token_id_fkey FOREIGN KEY (refresh_token_id) REFERENCES public.hrm_refresh_tokens(token_id);


--
-- Name: hrm_refresh_tokens hrm_refresh_tokens_auth_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hrm_refresh_tokens
    ADD CONSTRAINT hrm_refresh_tokens_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id);


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.hrm_permissions(permission_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_parent_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_parent_role_id_fkey FOREIGN KEY (parent_role_id) REFERENCES public.user_roles(id);


--
-- PostgreSQL database dump complete
--

\unrestrict 0NiEJYl0WpQRKVgPNYZgGNhb8M5zEKuY5TRH1b7tDuJIqrYvV0C5GDZbafGl6j8

