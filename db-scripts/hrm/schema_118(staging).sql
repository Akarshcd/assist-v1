-- schema_118.employee_tests definition

-- Drop table

-- DROP TABLE schema_118.employee_tests;

CREATE TABLE schema_118.employee_tests (
	test_id serial4 NOT NULL,
	test_type varchar(20) NOT NULL,
	start_date timestamp NOT NULL,
	end_date timestamp NOT NULL,
	duration_seconds int4 NOT NULL,
	created_by int4 NOT NULL,
	status varchar(20) NOT NULL,
	created_at timestamp DEFAULT now() NULL,
	CONSTRAINT employee_tests_pkey PRIMARY KEY (test_id),
	CONSTRAINT employee_tests_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'completed'::character varying, 'expired'::character varying])::text[]))),
	CONSTRAINT employee_tests_test_type_check CHECK (((test_type)::text = 'personality'::text))
);


-- schema_118.holidays definition

-- Drop table

-- DROP TABLE schema_118.holidays;

CREATE TABLE schema_118.holidays (
	id serial4 NOT NULL,
	holiday_name varchar(100) NOT NULL,
	holiday_date date NOT NULL,
	holiday_type varchar(50) NULL,
	country varchar(50) NULL,
	image_s3_key varchar(500) NULL,
	CONSTRAINT holidays_pkey PRIMARY KEY (id)
);


-- schema_118.leave_policy definition

-- Drop table

-- DROP TABLE schema_118.leave_policy;

CREATE TABLE schema_118.leave_policy (
	id serial4 NOT NULL,
	leave_type varchar(50) NOT NULL,
	last_update date NULL,
	notes text NULL,
	total_days int4 NULL,
	intern int4 NULL,
	country varchar NULL,
	CONSTRAINT leave_policy_pkey PRIMARY KEY (id)
);


-- schema_118.logs definition

-- Drop table

-- DROP TABLE schema_118.logs;

CREATE TABLE schema_118.logs (
	id serial4 NOT NULL,
	"level" text NOT NULL,
	message text NOT NULL,
	meta jsonb NULL,
	created_at timestamp DEFAULT now() NULL,
	CONSTRAINT logs_pkey PRIMARY KEY (id)
);


-- schema_118.onboarding definition

-- Drop table

-- DROP TABLE schema_118.onboarding;

CREATE TABLE schema_118.onboarding (
	onboarding_id serial4 NOT NULL,
	applicant_id int4 NOT NULL,
	employee_name varchar(255) NOT NULL,
	department_id int4 NOT NULL,
	job_role varchar(255) NOT NULL,
	job_type varchar(50) NOT NULL,
	"location" varchar(255) NOT NULL,
	assigned_manager_id int4 NULL,
	assigned_manager_name varchar(255) NULL,
	joining_date date NOT NULL,
	due_date date NOT NULL,
	onboarding_status varchar(50) DEFAULT 'Not Started'::character varying NOT NULL,
	created_by int4 NOT NULL,
	created_at timestamp DEFAULT now() NULL,
	updated_at timestamp DEFAULT now() NULL,
	employee_email varchar(255) NOT NULL,
	employee_phone varchar(20) NULL,
	temporary_password varchar(255) NULL,
	welcome_message text NULL,
	welcome_email_sent bool DEFAULT false NULL,
	welcome_email_sent_at timestamp NULL,
	office_email varchar(255) NULL,
	assigned_manager_email varchar NULL,
	email_body text NULL,
	CONSTRAINT onboarding_job_type_check CHECK (((job_type)::text = ANY ((ARRAY['Full-Time'::character varying, 'Part-Time'::character varying, 'Contract'::character varying, 'Intern'::character varying])::text[]))),
	CONSTRAINT onboarding_onboarding_status_check CHECK (((onboarding_status)::text = ANY ((ARRAY['Not Started'::character varying, 'In Progress'::character varying, 'Completed'::character varying])::text[]))),
	CONSTRAINT onboarding_pkey PRIMARY KEY (onboarding_id),
	CONSTRAINT uq_applicant_onboarding UNIQUE (applicant_id)
);
CREATE INDEX idx_onboarding_applicant ON schema_118.onboarding USING btree (applicant_id);
CREATE INDEX idx_onboarding_department_id ON schema_118.onboarding USING btree (department_id);
CREATE INDEX idx_onboarding_due_date ON schema_118.onboarding USING btree (due_date);
CREATE INDEX idx_onboarding_joining_date ON schema_118.onboarding USING btree (joining_date);
CREATE INDEX idx_onboarding_manager ON schema_118.onboarding USING btree (assigned_manager_id);
CREATE INDEX idx_onboarding_status ON schema_118.onboarding USING btree (onboarding_status);


-- schema_118.open_jobs definition

-- Drop table

-- DROP TABLE schema_118.open_jobs;

CREATE TABLE schema_118.open_jobs (
	job_id serial4 NOT NULL,
	job_title varchar(100) NULL,
	department_id int4 NULL,
	location_type varchar(50) NULL,
	job_type varchar(50) NULL,
	positions_available int4 DEFAULT 1 NOT NULL,
	posting_date date NULL,
	end_date date NULL,
	status varchar(20) DEFAULT 'Open'::character varying NULL,
	job_description text NULL,
	key_responsibilities _text DEFAULT '{}'::text[] NOT NULL,
	skills _text DEFAULT '{}'::text[] NOT NULL,
	experience varchar(50) NULL,
	job_code varchar(20) NULL,
	salary_range _int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	application_deadline date NULL,
	why_join text NULL,
	benefits jsonb DEFAULT '{}'::jsonb NULL,
	hiring_stages jsonb DEFAULT '[]'::jsonb NULL,
	CONSTRAINT open_jobs_pkey PRIMARY KEY (job_id)
);
CREATE INDEX idx_job_positions_department ON schema_118.open_jobs USING btree (department_id);
CREATE INDEX idx_job_positions_posting_date ON schema_118.open_jobs USING btree (posting_date);
CREATE INDEX idx_job_positions_status ON schema_118.open_jobs USING btree (status);

-- Table Triggers

create trigger update_job_positions_modtime before
update
    on
    schema_118.open_jobs for each row execute function update_modified_column();
create trigger update_open_jobs_updated_at before
update
    on
    schema_118.open_jobs for each row execute function update_updated_at_column();


-- schema_118.personality_test_questions definition

-- Drop table

-- DROP TABLE schema_118.personality_test_questions;

CREATE TABLE schema_118.personality_test_questions (
	question_id int4 NOT NULL,
	part bpchar(1) NOT NULL,
	question_text text NULL,
	option1_text text NOT NULL,
	option1_trait varchar(20) NOT NULL,
	option2_text text NOT NULL,
	option2_trait varchar(20) NOT NULL,
	option3_text text NOT NULL,
	option3_trait varchar(20) NOT NULL,
	CONSTRAINT chk_question_text CHECK ((((part = 'A'::bpchar) AND (question_text IS NULL)) OR ((part = 'B'::bpchar) AND (question_text IS NOT NULL)))),
	CONSTRAINT personality_test_questions_option1_trait_check CHECK (((option1_trait)::text = ANY ((ARRAY['O'::character varying, 'C'::character varying, 'E'::character varying, 'A'::character varying, 'N_low'::character varying, 'N_high'::character varying])::text[]))),
	CONSTRAINT personality_test_questions_option2_trait_check CHECK (((option2_trait)::text = ANY ((ARRAY['O'::character varying, 'C'::character varying, 'E'::character varying, 'A'::character varying, 'N_low'::character varying, 'N_high'::character varying])::text[]))),
	CONSTRAINT personality_test_questions_option3_trait_check CHECK (((option3_trait)::text = ANY ((ARRAY['O'::character varying, 'C'::character varying, 'E'::character varying, 'A'::character varying, 'N_low'::character varying, 'N_high'::character varying])::text[]))),
	CONSTRAINT personality_test_questions_part_check CHECK ((part = ANY (ARRAY['A'::bpchar, 'B'::bpchar]))),
	CONSTRAINT personality_test_questions_pkey PRIMARY KEY (question_id)
);


-- schema_118.employee_test_sessions definition

-- Drop table

-- DROP TABLE schema_118.employee_test_sessions;

CREATE TABLE schema_118.employee_test_sessions (
	test_id int4 NOT NULL,
	emp_id int4 NOT NULL,
	status varchar(20) NOT NULL,
	started_at timestamp NULL,
	completed_at timestamp NULL,
	elapsed_seconds int4 DEFAULT 0 NULL,
	last_seen timestamp DEFAULT now() NULL,
	CONSTRAINT employee_test_sessions_pkey PRIMARY KEY (test_id, emp_id),
	CONSTRAINT employee_test_sessions_status_check CHECK (((status)::text = ANY ((ARRAY['not_started'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'expired'::character varying])::text[]))),
	CONSTRAINT employee_test_sessions_test_id_fkey FOREIGN KEY (test_id) REFERENCES schema_118.employee_tests(test_id) ON DELETE CASCADE
);
CREATE INDEX idx_employee_test_sessions_emp ON schema_118.employee_test_sessions USING btree (emp_id);
CREATE INDEX idx_employee_test_sessions_emp_started ON schema_118.employee_test_sessions USING btree (emp_id, started_at DESC);
CREATE INDEX idx_employee_test_sessions_started_at ON schema_118.employee_test_sessions USING btree (started_at);
CREATE INDEX idx_employee_test_sessions_status_started ON schema_118.employee_test_sessions USING btree (status, started_at DESC);
CREATE INDEX idx_tests_emp_status_started ON schema_118.employee_test_sessions USING btree (emp_id, status, started_at DESC);

-- Table Triggers

create trigger trg_test_status_enforce before
update
    on
    schema_118.employee_test_sessions for each row execute function schema_118.trg_enforce_test_status();


-- schema_118.personality_test_responses definition

-- Drop table

-- DROP TABLE schema_118.personality_test_responses;

CREATE TABLE schema_118.personality_test_responses (
	response_id serial4 NOT NULL,
	test_id int4 NOT NULL,
	emp_id int4 NOT NULL,
	question_id int4 NOT NULL,
	option1_rank varchar(10) NOT NULL,
	option2_rank varchar(10) NOT NULL,
	option3_rank varchar(10) NOT NULL,
	created_at timestamp DEFAULT now() NULL,
	CONSTRAINT personality_test_responses_option1_rank_check CHECK (((option1_rank)::text = ANY ((ARRAY['Most'::character varying, 'Neutral'::character varying, 'Least'::character varying])::text[]))),
	CONSTRAINT personality_test_responses_option2_rank_check CHECK (((option2_rank)::text = ANY ((ARRAY['Most'::character varying, 'Neutral'::character varying, 'Least'::character varying])::text[]))),
	CONSTRAINT personality_test_responses_option3_rank_check CHECK (((option3_rank)::text = ANY ((ARRAY['Most'::character varying, 'Neutral'::character varying, 'Least'::character varying])::text[]))),
	CONSTRAINT personality_test_responses_pkey PRIMARY KEY (response_id),
	CONSTRAINT uq_test_emp_question_response UNIQUE (test_id, emp_id, question_id),
	CONSTRAINT fk_responses_sessions FOREIGN KEY (test_id,emp_id) REFERENCES schema_118.employee_test_sessions(test_id,emp_id) ON DELETE CASCADE,
	CONSTRAINT personality_test_responses_question_id_fkey FOREIGN KEY (question_id) REFERENCES schema_118.personality_test_questions(question_id) ON DELETE CASCADE
);
CREATE INDEX idx_responses_created_at ON schema_118.personality_test_responses USING btree (created_at DESC);
CREATE INDEX idx_responses_question ON schema_118.personality_test_responses USING btree (question_id);
CREATE INDEX idx_responses_test_emp ON schema_118.personality_test_responses USING btree (test_id, emp_id);


-- schema_118.personality_test_scores definition

-- Drop table

-- DROP TABLE schema_118.personality_test_scores;

CREATE TABLE schema_118.personality_test_scores (
	score_id serial4 NOT NULL,
	test_id int4 NOT NULL,
	emp_id int4 NOT NULL,
	status varchar(10) NOT NULL,
	openness numeric(5, 2) NULL,
	conscientiousness numeric(5, 2) NULL,
	extraversion numeric(5, 2) NULL,
	agreeableness numeric(5, 2) NULL,
	neuroticism numeric(5, 2) NULL,
	consistency numeric(5, 2) NULL,
	CONSTRAINT personality_test_scores_agreeableness_check CHECK (((agreeableness >= (0)::numeric) AND (agreeableness <= (100)::numeric))),
	CONSTRAINT personality_test_scores_conscientiousness_check CHECK (((conscientiousness >= (0)::numeric) AND (conscientiousness <= (100)::numeric))),
	CONSTRAINT personality_test_scores_consistency_check CHECK (((consistency >= (0)::numeric) AND (consistency <= (100)::numeric))),
	CONSTRAINT personality_test_scores_extraversion_check CHECK (((extraversion >= (0)::numeric) AND (extraversion <= (100)::numeric))),
	CONSTRAINT personality_test_scores_neuroticism_check CHECK (((neuroticism >= (0)::numeric) AND (neuroticism <= (100)::numeric))),
	CONSTRAINT personality_test_scores_openness_check CHECK (((openness >= (0)::numeric) AND (openness <= (100)::numeric))),
	CONSTRAINT personality_test_scores_pkey PRIMARY KEY (score_id),
	CONSTRAINT personality_test_scores_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying])::text[]))),
	CONSTRAINT uq_test_emp_score UNIQUE (test_id, emp_id),
	CONSTRAINT fk_scores_sessions FOREIGN KEY (test_id,emp_id) REFERENCES schema_118.employee_test_sessions(test_id,emp_id) ON DELETE CASCADE
);
CREATE INDEX idx_scores_emp ON schema_118.personality_test_scores USING btree (emp_id);
CREATE INDEX idx_scores_test_emp ON schema_118.personality_test_scores USING btree (test_id, emp_id);


-- schema_118.employee_test_question_order definition

-- Drop table

-- DROP TABLE schema_118.employee_test_question_order;

CREATE TABLE schema_118.employee_test_question_order (
	test_id int4 NOT NULL,
	emp_id int4 NOT NULL,
	question_id int4 NULL,
	order_no int4 NOT NULL,
	CONSTRAINT employee_test_question_order_pkey PRIMARY KEY (test_id, emp_id, order_no),
	CONSTRAINT uq_test_emp_question UNIQUE (test_id, emp_id, question_id),
	CONSTRAINT employee_test_question_order_question_id_fkey FOREIGN KEY (question_id) REFERENCES schema_118.personality_test_questions(question_id) ON DELETE CASCADE,
	CONSTRAINT employee_test_question_order_test_id_emp_id_fkey FOREIGN KEY (test_id,emp_id) REFERENCES schema_118.employee_test_sessions(test_id,emp_id) ON DELETE CASCADE
);
CREATE INDEX idx_question_order_lookup ON schema_118.employee_test_question_order USING btree (question_id);
CREATE INDEX idx_test_emp_order ON schema_118.employee_test_question_order USING btree (test_id, emp_id, order_no);


-- schema_118.applicants definition

-- Drop table

-- DROP TABLE schema_118.applicants;

CREATE TABLE schema_118.applicants (
	applicant_id serial4 NOT NULL,
	application_id varchar(20) NULL,
	job_id int4 NOT NULL,
	applicant_name varchar(100) NOT NULL,
	email varchar(100) NOT NULL,
	phone varchar(20) NULL,
	date_of_birth date NULL,
	gender varchar(10) NULL,
	address varchar(500) NULL,
	city varchar(100) NULL,
	country varchar(50) DEFAULT 'India'::character varying NULL,
	job_type varchar(50) NULL,
	experience varchar(50) NULL,
	highest_educational_qualification varchar(100) NULL,
	application_date date NOT NULL,
	preferred_joining_date date NULL,
	referral_emp_id int4 NULL,
	application_status varchar(30) DEFAULT 'Application Received'::character varying NULL,
	next_interview date NULL,
	documents jsonb DEFAULT '{}'::jsonb NULL,
	portfolio_link varchar(500) NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	dept_id int4 NULL,
	CONSTRAINT applicants_application_id_key UNIQUE (application_id),
	CONSTRAINT applicants_pkey PRIMARY KEY (applicant_id),
	CONSTRAINT unique_email_per_job UNIQUE (email, job_id)
);
CREATE INDEX idx_applicants_application_date ON schema_118.applicants USING btree (application_date);
CREATE INDEX idx_applicants_dept_id ON schema_118.applicants USING btree (dept_id);
CREATE INDEX idx_applicants_documents ON schema_118.applicants USING gin (documents);
CREATE INDEX idx_applicants_email ON schema_118.applicants USING btree (email);
CREATE INDEX idx_applicants_job_id ON schema_118.applicants USING btree (job_id);
CREATE INDEX idx_applicants_next_interview ON schema_118.applicants USING btree (next_interview);
CREATE INDEX idx_applicants_referral_emp ON schema_118.applicants USING btree (referral_emp_id);
CREATE INDEX idx_applicants_status ON schema_118.applicants USING btree (application_status);

-- Table Triggers

create trigger trigger_generate_application_id before
insert
    on
    schema_118.applicants for each row execute function schema_118.generate_application_id();
create trigger update_applicants_modtime before
update
    on
    schema_118.applicants for each row execute function update_modified_column();


-- schema_118.assets definition

-- Drop table

-- DROP TABLE schema_118.assets;

CREATE TABLE schema_118.assets (
	asset_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	asset_name varchar(255) NOT NULL,
	asset_description varchar(255) NOT NULL,
	issue_date date NOT NULL,
	return_date date NULL,
	reason_for_leaving varchar(500) NULL,
	asset_type varchar(10) NULL,
	asset_condition varchar(255) NULL,
	CONSTRAINT assets_asset_type_check CHECK (((asset_type)::text = ANY ((ARRAY['Software'::character varying, 'Hardware'::character varying])::text[]))),
	CONSTRAINT assets_pkey PRIMARY KEY (asset_id)
);


-- schema_118.certificates definition

-- Drop table

-- DROP TABLE schema_118.certificates;

CREATE TABLE schema_118.certificates (
	cer_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	title varchar(255) NOT NULL,
	description varchar(255) NOT NULL,
	"date" date NOT NULL,
	certificate_docs jsonb NULL,
	"year" int4 NULL,
	CONSTRAINT certificates_pkey PRIMARY KEY (cer_id)
);


-- schema_118.company_property definition

-- Drop table

-- DROP TABLE schema_118.company_property;

CREATE TABLE schema_118.company_property (
	property_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	property_name varchar(255) NOT NULL,
	property_type varchar(50) NOT NULL,
	property_id_code varchar(100) NULL,
	description text NULL,
	issue_date date NULL,
	return_date date NULL,
	"condition" varchar(50) NULL,
	created_at timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	created_by int4 NULL,
	updated_at timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	updated_by int4 NULL,
	CONSTRAINT company_property_condition_check CHECK (((condition)::text = ANY (ARRAY[('New'::character varying)::text, ('Good'::character varying)::text, ('Fair'::character varying)::text, ('Damaged'::character varying)::text, ('Returned'::character varying)::text]))),
	CONSTRAINT company_property_pkey PRIMARY KEY (property_id),
	CONSTRAINT company_property_property_id_code_key UNIQUE (property_id_code),
	CONSTRAINT company_property_property_type_check CHECK (((property_type)::text = ANY (ARRAY[('Hardware'::character varying)::text, ('Software'::character varying)::text])))
);
CREATE INDEX idx_company_property_emp_id ON schema_118.company_property USING btree (emp_id);
CREATE INDEX idx_company_property_issue_date ON schema_118.company_property USING btree (issue_date);
CREATE INDEX idx_company_property_type ON schema_118.company_property USING btree (property_type);


-- schema_118.employee_bank_details definition

-- Drop table

-- DROP TABLE schema_118.employee_bank_details;

CREATE TABLE schema_118.employee_bank_details (
	id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	account_holder_name text NULL,
	account_number text NULL,
	branch_name text NULL,
	bank_name varchar(100) NULL,
	bank_ifsc_code text NULL,
	country varchar(50) NULL,
	bank_doc jsonb NULL,
	encryption_key bytea NULL,
	encryption_key_version int4 DEFAULT 1 NULL,
	transit_number text NULL,
	institution_number text NULL,
	interac_id text NULL,
	pan_number text NULL,
	CONSTRAINT employee_bank_details_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_employee_bank_details_emp_id ON schema_118.employee_bank_details USING btree (emp_id);


-- schema_118.employee_contacts definition

-- Drop table

-- DROP TABLE schema_118.employee_contacts;

CREATE TABLE schema_118.employee_contacts (
	id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	"name" varchar(50) NULL,
	mobile varchar(50) NULL,
	gender varchar(20) NULL,
	relationship varchar(50) NULL,
	url varchar(100) NULL,
	email_id varchar(50) NULL,
	languages _text DEFAULT '{}'::text[] NULL,
	CONSTRAINT employee_contacts_pkey PRIMARY KEY (id)
);


-- schema_118.employee_offboarding definition

-- Drop table

-- DROP TABLE schema_118.employee_offboarding;

CREATE TABLE schema_118.employee_offboarding (
	offboarding_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	department_id int4 NULL,
	manager_id int4 NULL,
	date_of_joining date NULL,
	date_of_resignation date NULL,
	notice_period_duration int4 NULL,
	estimated_last_working_day date NULL,
	reason_for_resignation text NULL,
	status varchar(50) DEFAULT 'initiated'::character varying NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	emp_name varchar(255) NULL,
	manager_name varchar(255) NULL,
	job_role varchar(255) NULL,
	request_type varchar(30) NULL,
	department_name varchar(255) NULL,
	status_history jsonb DEFAULT '["submitted"]'::jsonb NOT NULL,
	retention_details jsonb DEFAULT '{}'::jsonb NULL,
	termination_details text NULL,
	termination_reason varchar(255) NULL,
	rejection_details text NULL,
	CONSTRAINT employee_offboarding_notice_period_duration_check CHECK ((notice_period_duration >= 0)),
	CONSTRAINT employee_offboarding_pkey PRIMARY KEY (offboarding_id),
	CONSTRAINT employee_offboarding_status_check CHECK (((status)::text = ANY (ARRAY['initiated'::text, 'in_review_manager'::text, 'in_review_hod'::text, 'in_review_hr'::text, 'approved'::text, 'rejected'::text, 'retained'::text, 'retention_initiated'::text, 'pending_termination_approval'::text, 'termination_scheduled'::text, 'termination_cancelled'::text, 'terminated'::text])))
);
CREATE INDEX idx_offboarding_created_at ON schema_118.employee_offboarding USING btree (created_at);
CREATE INDEX idx_offboarding_department ON schema_118.employee_offboarding USING btree (department_id);
CREATE INDEX idx_offboarding_employee ON schema_118.employee_offboarding USING btree (emp_id);
CREATE INDEX idx_offboarding_manager ON schema_118.employee_offboarding USING btree (manager_id);
CREATE INDEX idx_offboarding_status ON schema_118.employee_offboarding USING btree (status);

-- Table Triggers

create trigger update_employee_offboarding_updated_at before
update
    on
    schema_118.employee_offboarding for each row execute function update_updated_at_column();


-- schema_118.employee_referrals definition

-- Drop table

-- DROP TABLE schema_118.employee_referrals;

CREATE TABLE schema_118.employee_referrals (
	referral_id serial4 NOT NULL,
	application_id varchar(50) NOT NULL,
	referring_emp_id int4 NOT NULL,
	referring_emp_name varchar(255) NOT NULL,
	referring_emp_email varchar(255) NOT NULL,
	candidate_name varchar(255) NOT NULL,
	candidate_email varchar(255) NOT NULL,
	candidate_phone varchar(20) NULL,
	date_of_birth date NULL,
	gender varchar(20) NULL,
	address text NULL,
	city varchar(100) NULL,
	country varchar(100) NULL,
	job_id int4 NULL,
	experience int4 NULL,
	highest_educational_qualification varchar(255) NULL,
	application_date date DEFAULT CURRENT_DATE NULL,
	preferred_joining_date date NULL,
	documents jsonb DEFAULT '{}'::jsonb NULL,
	portfolio_link text NULL,
	referral_status varchar(50) DEFAULT 'Pending'::character varying NULL,
	referral_date date DEFAULT CURRENT_DATE NULL,
	status_updated_at timestamp NULL,
	status_updated_by int4 NULL,
	applicant_id int4 NULL,
	created_at timestamp DEFAULT now() NULL,
	updated_at timestamp DEFAULT now() NULL,
	created_by int4 NULL,
	CONSTRAINT employee_referrals_application_id_key UNIQUE (application_id),
	CONSTRAINT employee_referrals_pkey PRIMARY KEY (referral_id)
);
CREATE INDEX idx_employee_referrals_candidate_email ON schema_118.employee_referrals USING btree (candidate_email);
CREATE INDEX idx_employee_referrals_date ON schema_118.employee_referrals USING btree (referral_date);
CREATE INDEX idx_employee_referrals_emp_id ON schema_118.employee_referrals USING btree (referring_emp_id);
CREATE INDEX idx_employee_referrals_job_id ON schema_118.employee_referrals USING btree (job_id);
CREATE INDEX idx_employee_referrals_status ON schema_118.employee_referrals USING btree (referral_status);

-- Table Triggers

create trigger employee_referrals_timestamps_trigger before
insert
    or
update
    on
    schema_118.employee_referrals for each row execute function update_employee_referrals_timestamps();


-- schema_118.exit_feedback definition

-- Drop table

-- DROP TABLE schema_118.exit_feedback;

CREATE TABLE schema_118.exit_feedback (
	feedback_id serial4 NOT NULL,
	offboarding_id int4 NOT NULL,
	personal_email_id varchar(255) NULL,
	mobile_number varchar(20) NULL,
	items_returned jsonb NULL,
	liked_most text NULL,
	improvement_suggestions text NULL,
	would_rejoin bool NULL,
	company_feedback text NULL,
	join_alumni_network bool NULL,
	submitted_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	experience_ratings jsonb NULL,
	CONSTRAINT exit_feedback_pkey PRIMARY KEY (feedback_id)
);
CREATE INDEX idx_exit_feedback_offboarding ON schema_118.exit_feedback USING btree (offboarding_id);

-- Table Triggers

create trigger update_exit_feedback_updated_at before
update
    on
    schema_118.exit_feedback for each row execute function update_updated_at_column();


-- schema_118.hrm_employees definition

-- Drop table

-- DROP TABLE schema_118.hrm_employees;

CREATE TABLE schema_118.hrm_employees (
	emp_id serial4 NOT NULL,
	crm_id int4 NOT NULL,
	dob date NULL,
	address varchar(255) NULL,
	gender varchar(50) NULL,
	emergency_contact varchar(20) NULL,
	bank_details varchar(255) NULL,
	position_id int4 NULL,
	experience numeric(4, 2) NULL,
	highest_educational_qualification varchar(255) NULL,
	skillset _varchar NULL,
	personal_email varchar(50) NULL,
	user_role_id int4 NULL,
	employee_code varchar(50) NULL,
	dept_code varchar(50) NULL,
	temp_address varchar(255) NULL,
	emergency_contact_relationship varchar(100) NULL,
	aadhar jsonb NULL,
	pan jsonb NULL,
	passport jsonb NULL,
	drivers_license jsonb NULL,
	photo jsonb NULL,
	professional_photo jsonb NULL,
	hobbies _varchar NULL,
	country varchar NULL,
	marksheet_12th jsonb NULL,
	degree_certificates jsonb NULL,
	relieving_letter jsonb NULL,
	last_3_payslips jsonb NULL,
	address_proof jsonb NULL,
	immigration_doc jsonb NULL,
	sin jsonb NULL,
	void_check jsonb NULL,
	"external" bool DEFAULT false NULL,
	leave_allocations jsonb NULL,
	auth_id int4 NULL,
	is_finance_approver bool DEFAULT false NULL,
	software_poc int4 NULL,
	languages _text DEFAULT '{}'::text[] NULL,
	CONSTRAINT hrm_employees_auth_id_key UNIQUE (auth_id),
	CONSTRAINT hrm_employees_pkey PRIMARY KEY (emp_id),
	CONSTRAINT uq_hrm_employees_crm_id UNIQUE (crm_id)
);
CREATE INDEX idx_hrm_employees_languages ON schema_118.hrm_employees USING gin (languages);


-- schema_118.interviews definition

-- Drop table

-- DROP TABLE schema_118.interviews;

CREATE TABLE schema_118.interviews (
	interview_id serial4 NOT NULL,
	applicant_id int4 NOT NULL,
	job_id int4 NOT NULL,
	hiring_stage_id int4 NOT NULL,
	interviewer_ids jsonb NOT NULL,
	meeting_title varchar(255) NOT NULL,
	meeting_date date NOT NULL,
	from_time time NOT NULL,
	to_time time NOT NULL,
	timezone varchar(100) DEFAULT 'IST - Indian Standard Time'::character varying NULL,
	meeting_link text NULL,
	microsoft_meeting_id text NULL,
	meeting_notes text NULL,
	status varchar(50) DEFAULT 'scheduled'::character varying NULL,
	feedback jsonb NULL,
	scheduled_by int4 NOT NULL,
	created_at timestamp DEFAULT now() NULL,
	updated_at timestamp DEFAULT now() NULL,
	CONSTRAINT interviews_pkey PRIMARY KEY (interview_id)
);
CREATE INDEX idx_interview_applicant_id ON schema_118.interviews USING btree (applicant_id);
CREATE INDEX idx_interview_date ON schema_118.interviews USING btree (meeting_date);
CREATE INDEX idx_interview_feedback ON schema_118.interviews USING gin (feedback);
CREATE INDEX idx_interview_job_id ON schema_118.interviews USING btree (job_id);
CREATE INDEX idx_interview_scheduled_by ON schema_118.interviews USING btree (scheduled_by);
CREATE INDEX idx_interview_status ON schema_118.interviews USING btree (status);

-- Table Triggers

create trigger interview_timestamps_trigger before
insert
    or
update
    on
    schema_118.interviews for each row execute function schema_118.update_interview_timestamps();


-- schema_118.job_history definition

-- Drop table

-- DROP TABLE schema_118.job_history;

CREATE TABLE schema_118.job_history (
	job_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	company_name varchar(255) NOT NULL,
	job_title varchar(255) NOT NULL,
	start_date date NOT NULL,
	end_date date NULL,
	reason_for_leaving varchar(255) NULL,
	employment_type varchar(10) NULL,
	job_docs jsonb NULL,
	CONSTRAINT job_history_pkey PRIMARY KEY (job_id)
);


-- schema_118.job_requests definition

-- Drop table

-- DROP TABLE schema_118.job_requests;

CREATE TABLE schema_118.job_requests (
	request_job_id serial4 NOT NULL,
	requested_by_id int4 NOT NULL,
	department_id int4 NULL,
	job_title varchar(255) NOT NULL,
	reason text NULL,
	positions int4 DEFAULT 1 NOT NULL,
	priority varchar(20) NULL,
	work_type varchar(50) NULL,
	description text NULL,
	status varchar(20) DEFAULT 'pending'::character varying NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	experience varchar(50) DEFAULT '0-1 years'::character varying NULL,
	CONSTRAINT job_requests_pkey PRIMARY KEY (request_job_id),
	CONSTRAINT job_requests_priority_check CHECK (((priority)::text = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text]))),
	CONSTRAINT job_requests_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);
CREATE INDEX idx_job_requests_department ON schema_118.job_requests USING btree (department_id);

-- Table Triggers

create trigger update_job_requests_updated_at before
update
    on
    schema_118.job_requests for each row execute function update_updated_at_column();


-- schema_118.job_title definition

-- Drop table

-- DROP TABLE schema_118.job_title;

CREATE TABLE schema_118.job_title (
	job_id serial4 NOT NULL,
	job_title varchar(300) NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	"level" int4 NULL,
	notice_period varchar(50) NULL,
	status varchar(20) DEFAULT 'active'::character varying NULL,
	department_id int4 NULL,
	subdepartment_id int4 NULL,
	CONSTRAINT job_title_pkey PRIMARY KEY (job_id)
);
CREATE INDEX idx_job_title_created_by ON schema_118.job_title USING btree (created_by);
CREATE INDEX idx_job_title_title ON schema_118.job_title USING btree (job_title);
CREATE UNIQUE INDEX uq_job_title_dept ON schema_118.job_title USING btree (department_id, job_title);

-- Table Triggers

create trigger update_job_title_updated_at before
update
    on
    schema_118.job_title for each row execute function update_updated_at_column();


-- schema_118.job_title_scope definition

-- Drop table

-- DROP TABLE schema_118.job_title_scope;

CREATE TABLE schema_118.job_title_scope (
	scope_id serial4 NOT NULL,
	job_id int4 NOT NULL,
	department_id int4 NULL,
	subdepartment_id int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	created_by int4 NULL,
	CONSTRAINT job_title_scope_pkey PRIMARY KEY (scope_id),
	CONSTRAINT uq_job_scope UNIQUE (job_id, department_id, subdepartment_id)
);
CREATE INDEX idx_job_title_scope_department_id ON schema_118.job_title_scope USING btree (department_id);
CREATE INDEX idx_job_title_scope_dept_subdept ON schema_118.job_title_scope USING btree (department_id, subdepartment_id);
CREATE INDEX idx_job_title_scope_job_id ON schema_118.job_title_scope USING btree (job_id);
CREATE INDEX idx_job_title_scope_subdepartment_id ON schema_118.job_title_scope USING btree (subdepartment_id);


-- schema_118.leaves_applied definition

-- Drop table

-- DROP TABLE schema_118.leaves_applied;

CREATE TABLE schema_118.leaves_applied (
	id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	leave_type_id int4 NOT NULL,
	days numeric NOT NULL,
	start_date date NOT NULL,
	status varchar(20) DEFAULT 'pending'::character varying NOT NULL,
	withdraw_action bool DEFAULT false NULL,
	reason text NULL,
	approved_by int4 NULL,
	approved_date date NULL,
	created_at timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	end_date date NULL,
	docs jsonb NULL,
	day_type varchar(20) DEFAULT 'full_day'::character varying NULL,
	half_type varchar(20) DEFAULT NULL::character varying NULL,
	rejection_reason text NULL,
	rejected_at timestamp NULL,
	CONSTRAINT chk_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[]))),
	CONSTRAINT leaves_applied_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_leaves_applied_emp_id ON schema_118.leaves_applied USING btree (emp_id);
CREATE INDEX idx_leaves_applied_status ON schema_118.leaves_applied USING btree (status);


-- schema_118.milestone definition

-- Drop table

-- DROP TABLE schema_118.milestone;

CREATE TABLE schema_118.milestone (
	milestone_id serial4 NOT NULL,
	emp_id int4 NOT NULL,
	milestone varchar(255) NOT NULL,
	description varchar(255) NULL,
	"date" date NULL,
	CONSTRAINT milestone_pkey PRIMARY KEY (milestone_id)
);


-- schema_118.project_departments definition

-- Drop table

-- DROP TABLE schema_118.project_departments;

CREATE TABLE schema_118.project_departments (
	department_id int4 DEFAULT nextval('schema_118.project_departments_id_seq'::regclass) NOT NULL,
	department text NULL,
	manager_id int4 NULL,
	department_code varchar(25) NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	status varchar(20) DEFAULT 'active'::character varying NULL,
	CONSTRAINT project_departments_pkey PRIMARY KEY (department_id)
);
CREATE INDEX idx_project_departments_created_by ON schema_118.project_departments USING btree (created_by);
CREATE INDEX idx_project_departments_department_code ON schema_118.project_departments USING btree (department_code);
CREATE INDEX idx_project_departments_manager ON schema_118.project_departments USING btree (manager_id);

-- Table Triggers

create trigger update_project_departments_updated_at before
update
    on
    schema_118.project_departments for each row execute function update_updated_at_column();


-- schema_118.resume_bank definition

-- Drop table

-- DROP TABLE schema_118.resume_bank;

CREATE TABLE schema_118.resume_bank (
	resume_bank_id serial4 NOT NULL,
	applicant_name varchar(255) NOT NULL,
	email varchar(255) NOT NULL,
	phone varchar(20) NULL,
	date_of_birth date NULL,
	gender varchar(20) NULL,
	address text NULL,
	city varchar(100) NULL,
	country varchar(100) NULL,
	experience varchar(50) NULL,
	highest_educational_qualification text NULL,
	portfolio_link text NULL,
	application_id varchar(100) NULL,
	job_id int4 NULL,
	job_type varchar(50) NULL,
	application_date date NOT NULL,
	preferred_joining_date date NULL,
	referral_emp_id int4 NULL,
	dept_id int4 NULL,
	documents jsonb DEFAULT '{}'::jsonb NULL,
	rejected_reason varchar(255) NOT NULL,
	rejection_source varchar(50) NOT NULL,
	rejection_detail text NULL,
	rejected_by int4 NULL,
	rejected_date timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	status varchar(50) DEFAULT 'Available'::character varying NULL,
	moved_to_applicant_id int4 NULL,
	moved_to_applicant_date timestamp NULL,
	moved_by int4 NULL,
	created_at timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	created_by int4 NULL,
	updated_at timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	updated_by int4 NULL,
	CONSTRAINT chk_email_format CHECK (((email)::text ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'::text)),
	CONSTRAINT chk_rejection_source CHECK (((rejection_source)::text = ANY ((ARRAY['applicant'::character varying, 'referral'::character varying, 'interview'::character varying])::text[]))),
	CONSTRAINT chk_status CHECK (((status)::text = ANY ((ARRAY['Available'::character varying, 'Moved to Applicant'::character varying, 'Archived'::character varying])::text[]))),
	CONSTRAINT resume_bank_pkey PRIMARY KEY (resume_bank_id)
);
CREATE INDEX idx_resume_bank_applicant_name ON schema_118.resume_bank USING btree (applicant_name);
CREATE INDEX idx_resume_bank_application_date ON schema_118.resume_bank USING btree (application_date);
CREATE INDEX idx_resume_bank_created_at ON schema_118.resume_bank USING btree (created_at);
CREATE INDEX idx_resume_bank_email ON schema_118.resume_bank USING btree (email);
CREATE INDEX idx_resume_bank_experience ON schema_118.resume_bank USING btree (experience);
CREATE INDEX idx_resume_bank_job_experience ON schema_118.resume_bank USING btree (job_id, experience);
CREATE INDEX idx_resume_bank_job_id ON schema_118.resume_bank USING btree (job_id);
CREATE INDEX idx_resume_bank_rejected_date ON schema_118.resume_bank USING btree (rejected_date);
CREATE INDEX idx_resume_bank_rejected_reason ON schema_118.resume_bank USING btree (rejected_reason);
CREATE INDEX idx_resume_bank_rejection_source ON schema_118.resume_bank USING btree (rejection_source);
CREATE INDEX idx_resume_bank_rejection_source_reason ON schema_118.resume_bank USING btree (rejection_source, rejected_reason);
CREATE INDEX idx_resume_bank_search ON schema_118.resume_bank USING gin (to_tsvector('english'::regconfig, (COALESCE(applicant_name, ''::character varying))::text));
CREATE INDEX idx_resume_bank_status ON schema_118.resume_bank USING btree (status);
CREATE INDEX idx_resume_bank_status_job ON schema_118.resume_bank USING btree (status, job_id);
CREATE UNIQUE INDEX idx_resume_bank_unique_candidate ON schema_118.resume_bank USING btree (email, job_id) WHERE ((status)::text <> 'Archived'::text);

-- Table Triggers

create trigger trigger_resume_bank_updated_at before
update
    on
    schema_118.resume_bank for each row execute function update_resume_bank_updated_at();
create trigger trigger_update_move_status before
update
    on
    schema_118.resume_bank for each row execute function update_move_status();


-- schema_118.sub_department definition

-- Drop table

-- DROP TABLE schema_118.sub_department;

CREATE TABLE schema_118.sub_department (
	subdepartment_id int4 DEFAULT nextval('schema_118.sub_department_id_seq'::regclass) NOT NULL,
	department_id int4 NULL,
	manager_id int4 NULL,
	subdepartment_name varchar(255) NULL,
	subdepartment_code varchar(30) NULL,
	sharepoint_site_name varchar(255) NULL,
	sharepoint_site_id varchar(300) NULL,
	created_by int4 NOT NULL,
	updated_by int4 NULL,
	created_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz DEFAULT CURRENT_TIMESTAMP NULL,
	status varchar(20) DEFAULT 'active'::character varying NULL,
	CONSTRAINT chk_sub_department_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[]))),
	CONSTRAINT sub_department_pkey PRIMARY KEY (subdepartment_id),
	CONSTRAINT uq_sub_department UNIQUE (department_id, subdepartment_name)
);
CREATE INDEX idx_sub_department_code ON schema_118.sub_department USING btree (subdepartment_code);
CREATE INDEX idx_sub_department_created_by ON schema_118.sub_department USING btree (created_by);
CREATE INDEX idx_sub_department_department ON schema_118.sub_department USING btree (department_id);
CREATE INDEX idx_sub_department_manager ON schema_118.sub_department USING btree (manager_id);

-- Table Triggers

create trigger update_sub_department_updated_at before
update
    on
    schema_118.sub_department for each row execute function update_updated_at_column();
create trigger trg_sync_scope_on_subdept_move after
update
    of department_id on
    schema_118.sub_department for each row execute function schema_118.sync_scope_on_subdept_move();


-- schema_118.applicants foreign keys

ALTER TABLE schema_118.applicants ADD CONSTRAINT fk_applicants_job_id FOREIGN KEY (job_id) REFERENCES schema_118.open_jobs(job_id) ON DELETE CASCADE;
ALTER TABLE schema_118.applicants ADD CONSTRAINT fk_applicants_referral_emp FOREIGN KEY (referral_emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;


-- schema_118.assets foreign keys

ALTER TABLE schema_118.assets ADD CONSTRAINT assets_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.certificates foreign keys

ALTER TABLE schema_118.certificates ADD CONSTRAINT certificates_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.company_property foreign keys

ALTER TABLE schema_118.company_property ADD CONSTRAINT fk_emp_id FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.employee_bank_details foreign keys

ALTER TABLE schema_118.employee_bank_details ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.employee_contacts foreign keys

ALTER TABLE schema_118.employee_contacts ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.employee_offboarding foreign keys

ALTER TABLE schema_118.employee_offboarding ADD CONSTRAINT fk_offboarding_employee FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;
ALTER TABLE schema_118.employee_offboarding ADD CONSTRAINT fk_offboarding_manager FOREIGN KEY (manager_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;


-- schema_118.employee_referrals foreign keys

ALTER TABLE schema_118.employee_referrals ADD CONSTRAINT fk_referral_employee FOREIGN KEY (referring_emp_id) REFERENCES schema_118.hrm_employees(emp_id);
ALTER TABLE schema_118.employee_referrals ADD CONSTRAINT fk_referral_job FOREIGN KEY (job_id) REFERENCES schema_118.open_jobs(job_id);


-- schema_118.exit_feedback foreign keys

ALTER TABLE schema_118.exit_feedback ADD CONSTRAINT fk_feedback_offboarding FOREIGN KEY (offboarding_id) REFERENCES schema_118.employee_offboarding(offboarding_id) ON DELETE CASCADE;


-- schema_118.hrm_employees foreign keys

ALTER TABLE schema_118.hrm_employees ADD CONSTRAINT fk_user_roles FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id);
ALTER TABLE schema_118.hrm_employees ADD CONSTRAINT hrm_employees_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES public.hrm_auth(auth_id);


-- schema_118.interviews foreign keys

ALTER TABLE schema_118.interviews ADD CONSTRAINT fk_interview_applicant FOREIGN KEY (applicant_id) REFERENCES schema_118.applicants(applicant_id) ON DELETE CASCADE;
ALTER TABLE schema_118.interviews ADD CONSTRAINT fk_interview_job FOREIGN KEY (job_id) REFERENCES schema_118.open_jobs(job_id) ON DELETE CASCADE;


-- schema_118.job_history foreign keys

ALTER TABLE schema_118.job_history ADD CONSTRAINT job_history_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.job_requests foreign keys

ALTER TABLE schema_118.job_requests ADD CONSTRAINT fk_job_requests_requested_by FOREIGN KEY (requested_by_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;


-- schema_118.job_title foreign keys

ALTER TABLE schema_118.job_title ADD CONSTRAINT fk_job_title_department FOREIGN KEY (department_id) REFERENCES schema_118.project_departments(department_id) ON DELETE CASCADE;
ALTER TABLE schema_118.job_title ADD CONSTRAINT fk_job_title_sub_department FOREIGN KEY (subdepartment_id) REFERENCES schema_118.sub_department(subdepartment_id) ON DELETE SET NULL;
ALTER TABLE schema_118.job_title ADD CONSTRAINT fk_job_title_subdepartment FOREIGN KEY (subdepartment_id) REFERENCES schema_118.sub_department(subdepartment_id) ON DELETE SET NULL;


-- schema_118.job_title_scope foreign keys

ALTER TABLE schema_118.job_title_scope ADD CONSTRAINT fk_scope_department_id FOREIGN KEY (department_id) REFERENCES schema_118.project_departments(department_id);
ALTER TABLE schema_118.job_title_scope ADD CONSTRAINT fk_scope_job_id FOREIGN KEY (job_id) REFERENCES schema_118.job_title(job_id) ON DELETE CASCADE;
ALTER TABLE schema_118.job_title_scope ADD CONSTRAINT fk_scope_subdepartment_id FOREIGN KEY (subdepartment_id) REFERENCES schema_118.sub_department(subdepartment_id);


-- schema_118.leaves_applied foreign keys

ALTER TABLE schema_118.leaves_applied ADD CONSTRAINT fk_approver FOREIGN KEY (approved_by) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;
ALTER TABLE schema_118.leaves_applied ADD CONSTRAINT fk_employee FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;
ALTER TABLE schema_118.leaves_applied ADD CONSTRAINT fk_leave_policy FOREIGN KEY (leave_type_id) REFERENCES schema_118.leave_policy(id) ON DELETE RESTRICT;


-- schema_118.milestone foreign keys

ALTER TABLE schema_118.milestone ADD CONSTRAINT milestone_emp_id_fkey FOREIGN KEY (emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE CASCADE;


-- schema_118.project_departments foreign keys

ALTER TABLE schema_118.project_departments ADD CONSTRAINT fk_project_departments_manager FOREIGN KEY (manager_id) REFERENCES schema_118.hrm_employees(crm_id) ON DELETE SET NULL;


-- schema_118.resume_bank foreign keys

ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_created_by FOREIGN KEY (created_by) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_job FOREIGN KEY (job_id) REFERENCES schema_118.open_jobs(job_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_moved_by FOREIGN KEY (moved_by) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_moved_to_applicant FOREIGN KEY (moved_to_applicant_id) REFERENCES schema_118.applicants(applicant_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_referral_emp FOREIGN KEY (referral_emp_id) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_rejected_by FOREIGN KEY (rejected_by) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;
ALTER TABLE schema_118.resume_bank ADD CONSTRAINT fk_resume_bank_updated_by FOREIGN KEY (updated_by) REFERENCES schema_118.hrm_employees(emp_id) ON DELETE SET NULL;


-- schema_118.sub_department foreign keys

ALTER TABLE schema_118.sub_department ADD CONSTRAINT fk_project_sub_department_department FOREIGN KEY (department_id) REFERENCES schema_118.project_departments(department_id) ON DELETE CASCADE;
ALTER TABLE schema_118.sub_department ADD CONSTRAINT fk_project_sub_department_manager FOREIGN KEY (manager_id) REFERENCES schema_118.hrm_employees(crm_id) ON DELETE SET NULL;