

CREATE TABLE public.assignments (
  assignment_id integer NOT NULL DEFAULT nextval('assignments_assignment_id_seq'::regclass),
  project_id integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  description text,
  pay_date date,
  pay_method character varying,
  amount numeric,
  CONSTRAINT assignments_pkey PRIMARY KEY (assignment_id),
  CONSTRAINT fk_assignments_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id)
);

CREATE TABLE public.budget_items (
  item_id integer NOT NULL DEFAULT nextval('budget_items_item_id_seq'::regclass),
  budget_id integer NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL,
  total_price numeric DEFAULT ((quantity)::numeric * unit_price),
  item_name text,
  CONSTRAINT budget_items_pkey PRIMARY KEY (item_id),
  CONSTRAINT fk_budget_items_budget FOREIGN KEY (budget_id) REFERENCES public.budgets(budget_id)
);

CREATE TABLE public.budgets (
  budget_id integer NOT NULL DEFAULT nextval('budgets_budget_id_seq'::regclass),
  project_id integer NOT NULL,
  budget_date date DEFAULT CURRENT_DATE,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  description text,
  gestion_amount numeric DEFAULT 0,
  gestion_percentage numeric DEFAULT 0,
  gg_amount numeric DEFAULT 0,
  gg_percentage numeric DEFAULT 0,
  subtotal numeric DEFAULT 0,
  total numeric DEFAULT 0,
  CONSTRAINT budgets_pkey PRIMARY KEY (budget_id),
  CONSTRAINT fk_budgets_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id)
);

CREATE TABLE public.clients (
  client_id integer NOT NULL DEFAULT nextval('clients_client_id_seq'::regclass),
  name character varying NOT NULL,
  last_name character varying NOT NULL,
  email character varying,
  phone_number character varying,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  user_id uuid,
  client_type character varying NOT NULL DEFAULT 'Persona'::character varying,
  CONSTRAINT clients_pkey PRIMARY KEY (client_id),
  CONSTRAINT fk_clients_user FOREIGN KEY (user_id) REFERENCES public.users(user_id)
);

CREATE TABLE public.counters (
  name text NOT NULL,
  value integer NOT NULL DEFAULT 0,
  CONSTRAINT counters_pkey PRIMARY KEY (name)
);

CREATE TABLE public.expense_details (
  detail_id integer NOT NULL DEFAULT nextval('expense_details_detail_id_seq'::regclass),
  expense_id integer NOT NULL,
  detail_type character varying NOT NULL CHECK (detail_type::text = ANY (ARRAY['MANO_OBRA'::character varying, 'COLACION'::character varying, 'GASTOS_VARIOS'::character varying]::text[])),
  description text,
  amount numeric NOT NULL CHECK (amount >= 0::numeric),
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT expense_details_pkey PRIMARY KEY (detail_id),
  CONSTRAINT fk_expense_details_expense FOREIGN KEY (expense_id) REFERENCES public.expenses(expense_id)
);

CREATE TABLE public.expenses (
  expense_id integer NOT NULL DEFAULT nextval('expenses_expense_id_seq'::regclass),
  project_id integer NOT NULL,
  expense_date date NOT NULL DEFAULT CURRENT_DATE,
  expense_type character varying NOT NULL CHECK (expense_type::text = ANY (ARRAY['DIA_COMPLETO'::character varying, 'GASTO_GENERAL'::character varying]::text[])),
  description text,
  total_amount numeric NOT NULL CHECK (total_amount >= 0::numeric),
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  user_id uuid,
  CONSTRAINT expenses_pkey PRIMARY KEY (expense_id),
  CONSTRAINT fk_expenses_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT fk_expenses_user FOREIGN KEY (user_id) REFERENCES public.users(user_id)
);

CREATE TABLE public.group_items (
  id integer NOT NULL DEFAULT nextval('group_items_id_seq'::regclass),
  group_id integer NOT NULL,
  material_id integer NOT NULL,
  CONSTRAINT group_items_pkey PRIMARY KEY (id),
  CONSTRAINT fk_group_items_group FOREIGN KEY (group_id) REFERENCES public.group_material(group_id),
  CONSTRAINT fk_group_items_material FOREIGN KEY (material_id) REFERENCES public.material(material_id)
);

CREATE TABLE public.group_material (
  group_id integer NOT NULL DEFAULT nextval('group_material_group_id_seq'::regclass),
  name character varying NOT NULL,
  description text,
  user_id uuid NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT group_material_pkey PRIMARY KEY (group_id),
  CONSTRAINT fk_group_material_user FOREIGN KEY (user_id) REFERENCES public.users(user_id)
);

CREATE TABLE public.labour (
  labour_id integer NOT NULL DEFAULT nextval('labour_labour_id_seq'::regclass),
  project_id integer NOT NULL,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  pay_date date NOT NULL,
  description text,
  pay_method character varying DEFAULT 'Efectivo'::character varying,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT labour_pkey PRIMARY KEY (labour_id),
  CONSTRAINT fk_labour_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id)
);

CREATE TABLE public.material (
  material_id integer NOT NULL DEFAULT nextval('material_material_id_seq'::regclass),
  name character varying NOT NULL,
  price numeric,
  brand character varying,
  sku character varying,
  supplier character varying,
  category character varying,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  user_id uuid,
  urlimg text,
  CONSTRAINT material_pkey PRIMARY KEY (material_id),
  CONSTRAINT fk_material_user FOREIGN KEY (user_id) REFERENCES public.users(user_id)
);

CREATE TABLE public.payments (
  payment_id integer NOT NULL DEFAULT nextval('payments_payment_id_seq'::regclass),
  project_id integer NOT NULL,
  budget_id integer,
  rendition_id integer,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  pay_date date DEFAULT CURRENT_DATE,
  pay_method character varying,
  description text,
  amount numeric NOT NULL,
  payment_type character varying,
  assignment_id integer,
  labour_id integer,
  CONSTRAINT payments_pkey PRIMARY KEY (payment_id),
  CONSTRAINT fk_payments_budget FOREIGN KEY (budget_id) REFERENCES public.budgets(budget_id),
  CONSTRAINT fk_payments_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT fk_payments_rendition FOREIGN KEY (rendition_id) REFERENCES public.rendition(rendition_id),
  CONSTRAINT payments_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.assignments(assignment_id),
  CONSTRAINT payments_labour_id_fkey FOREIGN KEY (labour_id) REFERENCES public.labour(labour_id)
);

CREATE TABLE public.plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL UNIQUE,
  price numeric NOT NULL,
  description text,
  features jsonb NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT plans_pkey PRIMARY KEY (id)
);

CREATE TABLE public.project_material_items (
  id integer NOT NULL DEFAULT nextval('attached_group_items_id_seq'::regclass),
  group_id integer NOT NULL,
  material_id integer NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  source_group_id integer,
  group_name text,
  original_group_id integer,
  CONSTRAINT project_material_items_pkey PRIMARY KEY (id),
  CONSTRAINT attached_group_items_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.material(material_id),
  CONSTRAINT fk_project_material_items_list FOREIGN KEY (group_id) REFERENCES public.project_material_list(group_id),
  CONSTRAINT fk_original_group FOREIGN KEY (original_group_id) REFERENCES public.group_material(group_id)
);

CREATE TABLE public.project_material_list (
  group_id integer NOT NULL DEFAULT nextval('attached_group_material_group_id_seq'::regclass),
  name character varying NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  project_id integer NOT NULL UNIQUE,
  description text,
  user_id uuid,
  CONSTRAINT project_material_list_pkey PRIMARY KEY (group_id),
  CONSTRAINT fk_attached_group_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id),
  CONSTRAINT fk_attached_group_user FOREIGN KEY (user_id) REFERENCES public.users(user_id)
);

CREATE TABLE public.projects (
  project_id integer NOT NULL DEFAULT nextval('projects_project_id_seq'::regclass),
  project_name character varying NOT NULL,
  quote_number character varying,
  start_date date,
  status character varying DEFAULT 'Activo'::character varying,
  client_id integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  latitude numeric,
  longitude numeric,
  city character varying,
  user_address text,
  address_text text,
  location_source character varying CHECK ((location_source::text = ANY (ARRAY['map_picker'::character varying, 'city_center'::character varying]::text[])) OR location_source IS NULL),
  CONSTRAINT projects_pkey PRIMARY KEY (project_id),
  CONSTRAINT fk_projects_client FOREIGN KEY (client_id) REFERENCES public.clients(client_id)
);

CREATE TABLE public.rendition (
  rendition_id integer NOT NULL DEFAULT nextval('rendition_rendition_id_seq'::regclass),
  project_id integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  description text,
  total numeric DEFAULT 0,
  CONSTRAINT rendition_pkey PRIMARY KEY (rendition_id),
  CONSTRAINT fk_rendition_project FOREIGN KEY (project_id) REFERENCES public.projects(project_id)
);

CREATE TABLE public.rendition_items (
  id integer NOT NULL DEFAULT nextval('rendition_items_id_seq'::regclass),
  rendition_id integer NOT NULL,
  material_id integer,
  quantity integer NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL,
  total_price numeric DEFAULT ((quantity)::numeric * unit_price),
  fecha date,
  detalle text,
  proveedor text,
  folio text,
  total numeric,
  CONSTRAINT rendition_items_pkey PRIMARY KEY (id),
  CONSTRAINT fk_rendition_items_material FOREIGN KEY (material_id) REFERENCES public.material(material_id),
  CONSTRAINT fk_rendition_items_rendition FOREIGN KEY (rendition_id) REFERENCES public.rendition(rendition_id)
);

CREATE TABLE public.users (
  email character varying NOT NULL UNIQUE,
  name character varying NOT NULL,
  last_name character varying NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  user_id uuid NOT NULL,
  phone character varying,
  avatar_url text,
  brand_url text,
  brand_name text,
  provider text DEFAULT 'normal'::text,
  plan_id uuid,
  plan_expiration date,
  plan_started_at timestamp with time zone,
  CONSTRAINT users_pkey PRIMARY KEY (user_id),
  CONSTRAINT users_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id)
);