

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) RETURNS TABLE("project_id" integer, "total_rendicion" numeric, "total_asignado" numeric, "saldo_rendicion" numeric, "estado_rendicion" "text", "total_presupuesto" numeric, "total_abonado" numeric, "saldo_presupuesto" numeric, "porcentaje_pagado" numeric, "estado_presupuesto" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total_asignado NUMERIC := 0;
    v_total_abonado NUMERIC := 0;
    v_total_rendicion NUMERIC := 0;
    v_total_presupuesto NUMERIC := 0;
BEGIN
    -- Obtener totales de payments
    SELECT 
        COALESCE(SUM(CASE WHEN payment_type = 'asignacion' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN payment_type = 'abono_mo' THEN amount ELSE 0 END), 0)
    INTO v_total_asignado, v_total_abonado
    FROM payments
    WHERE payments.project_id = p_project_id;
    
    -- Obtener total de rendición desde la tabla rendition
    SELECT COALESCE(SUM(total), 0) INTO v_total_rendicion
    FROM rendition WHERE rendition.project_id = p_project_id;
    
    -- Obtener total de presupuesto desde la tabla budgets
    SELECT COALESCE(SUM(total), 0) INTO v_total_presupuesto
    FROM budgets WHERE budgets.project_id = p_project_id;
    
    RETURN QUERY SELECT
        p_project_id,
        v_total_rendicion,
        v_total_asignado,
        (v_total_rendicion - v_total_asignado),
        CASE 
            WHEN (v_total_rendicion - v_total_asignado) <= 0 THEN 'PAGADO'::TEXT
            ELSE 'PENDIENTE'::TEXT
        END,
        v_total_presupuesto,
        v_total_abonado,
        (v_total_presupuesto - v_total_abonado),
        CASE 
            WHEN v_total_presupuesto > 0 
            THEN ROUND((v_total_abonado / v_total_presupuesto * 100)::NUMERIC, 2)
            ELSE 0::NUMERIC
        END,
        CASE 
            WHEN (v_total_presupuesto - v_total_abonado) <= 0 THEN 'PAGADO'::TEXT
            ELSE 'PENDIENTE'::TEXT
        END;
END;
$$;


ALTER FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) IS 'Devuelve un resumen completo de pagos para un proyecto específico.
Incluye cálculos de saldos y estados.';



CREATE OR REPLACE FUNCTION "public"."increment_counter"("counter_name" "text") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
declare
  new_val int;
begin
  update counters
  set value = value + 1
  where name = counter_name
  returning value into new_val;

  if not found then
    raise exception 'Counter "%", no existe', counter_name;
  end if;

  return new_val;
end;
$$;


ALTER FUNCTION "public"."increment_counter"("counter_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_assignment_to_payment"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Insertar nuevo pago cuando se crea una asignación
        INSERT INTO payments (
            assignment_id,
            project_id,
            pay_date,
            pay_method,
            description,
            amount,
            payment_type,
            created_at
        ) VALUES (
            NEW.assignment_id,
            NEW.project_id,
            NEW.pay_date,
            NEW.pay_method,
            NEW.description,
            NEW.amount,
            'asignacion',
            NEW.created_at
        );
        RETURN NEW;
        
    ELSIF (TG_OP = 'UPDATE') THEN
        -- Actualizar el pago cuando se modifica una asignación
        UPDATE payments
        SET 
            pay_date = NEW.pay_date,
            pay_method = NEW.pay_method,
            description = NEW.description,
            amount = NEW.amount
        WHERE assignment_id = NEW.assignment_id
          AND payment_type = 'asignacion';
        RETURN NEW;
        
    ELSIF (TG_OP = 'DELETE') THEN
        -- Eliminar el pago cuando se elimina una asignación
        DELETE FROM payments
        WHERE assignment_id = OLD.assignment_id
          AND payment_type = 'asignacion';
        RETURN OLD;
    END IF;
END;
$$;


ALTER FUNCTION "public"."sync_assignment_to_payment"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_assignment_to_payment"() IS 'Sincroniza automáticamente la tabla assignments con payments. 
Se ejecuta en INSERT, UPDATE y DELETE.';



CREATE OR REPLACE FUNCTION "public"."sync_labour_to_payment"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Insertar nuevo pago cuando se crea un abono M.O.
        INSERT INTO payments (
            labour_id,
            project_id,
            pay_date,
            pay_method,
            description,
            amount,
            payment_type,
            created_at
        ) VALUES (
            NEW.labour_id,
            NEW.project_id,
            NEW.pay_date,
            NEW.pay_method,
            NEW.description,
            NEW.amount,
            'abono_mo',
            NEW.created_at
        );
        RETURN NEW;
        
    ELSIF (TG_OP = 'UPDATE') THEN
        -- Actualizar el pago cuando se modifica un abono M.O.
        UPDATE payments
        SET 
            pay_date = NEW.pay_date,
            pay_method = NEW.pay_method,
            description = NEW.description,
            amount = NEW.amount
        WHERE labour_id = NEW.labour_id
          AND payment_type = 'abono_mo';
        RETURN NEW;
        
    ELSIF (TG_OP = 'DELETE') THEN
        -- Eliminar el pago cuando se elimina un abono M.O.
        DELETE FROM payments
        WHERE labour_id = OLD.labour_id
          AND payment_type = 'abono_mo';
        RETURN OLD;
    END IF;
END;
$$;


ALTER FUNCTION "public"."sync_labour_to_payment"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_labour_to_payment"() IS 'Sincroniza automáticamente la tabla labour con payments. 
Se ejecuta en INSERT, UPDATE y DELETE.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."assignments" (
    "assignment_id" integer NOT NULL,
    "project_id" integer NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "description" "text",
    "pay_date" "date",
    "pay_method" character varying(100),
    "amount" numeric(15,2)
);


ALTER TABLE "public"."assignments" OWNER TO "postgres";


COMMENT ON TABLE "public"."assignments" IS 'Tabla de asignaciones y pagos de proyectos';



CREATE SEQUENCE IF NOT EXISTS "public"."assignments_assignment_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."assignments_assignment_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."assignments_assignment_id_seq" OWNED BY "public"."assignments"."assignment_id";



CREATE TABLE IF NOT EXISTS "public"."attached_group_items" (
    "id" integer NOT NULL,
    "group_id" integer NOT NULL,
    "material_id" integer NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."attached_group_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."attached_group_items" IS 'Ítems de grupos de materiales adjuntos';



CREATE SEQUENCE IF NOT EXISTS "public"."attached_group_items_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."attached_group_items_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."attached_group_items_id_seq" OWNED BY "public"."attached_group_items"."id";



CREATE TABLE IF NOT EXISTS "public"."attached_group_material" (
    "group_id" integer NOT NULL,
    "name" character varying(255) NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "project_id" integer NOT NULL,
    "description" "text",
    "status" character varying(50) DEFAULT 'Activo'::character varying
);


ALTER TABLE "public"."attached_group_material" OWNER TO "postgres";


COMMENT ON TABLE "public"."attached_group_material" IS 'Grupos de materiales adjuntos a proyectos';



CREATE SEQUENCE IF NOT EXISTS "public"."attached_group_material_group_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."attached_group_material_group_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."attached_group_material_group_id_seq" OWNED BY "public"."attached_group_material"."group_id";



CREATE TABLE IF NOT EXISTS "public"."budget_items" (
    "item_id" integer NOT NULL,
    "budget_id" integer NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(15,2) NOT NULL,
    "total_price" numeric(15,2) GENERATED ALWAYS AS ((("quantity")::numeric * "unit_price")) STORED,
    "item_name" "text"
);


ALTER TABLE "public"."budget_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."budget_items" IS 'Ítems detallados de presupuestos';



CREATE SEQUENCE IF NOT EXISTS "public"."budget_items_item_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."budget_items_item_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."budget_items_item_id_seq" OWNED BY "public"."budget_items"."item_id";



CREATE TABLE IF NOT EXISTS "public"."budgets" (
    "budget_id" integer NOT NULL,
    "project_id" integer NOT NULL,
    "budget_date" "date" DEFAULT CURRENT_DATE,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "description" "text",
    "gestion_amount" numeric(15,2) DEFAULT 0,
    "gestion_percentage" numeric(5,2) DEFAULT 0,
    "gg_amount" numeric(15,2) DEFAULT 0,
    "gg_percentage" numeric(5,2) DEFAULT 0,
    "subtotal" numeric(15,2) DEFAULT 0,
    "total" numeric(15,2) DEFAULT 0
);


ALTER TABLE "public"."budgets" OWNER TO "postgres";


COMMENT ON TABLE "public"."budgets" IS 'Presupuestos de proyectos';



CREATE SEQUENCE IF NOT EXISTS "public"."budgets_budget_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."budgets_budget_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."budgets_budget_id_seq" OWNED BY "public"."budgets"."budget_id";



CREATE TABLE IF NOT EXISTS "public"."clients" (
    "client_id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "last_name" character varying(100) NOT NULL,
    "email" character varying(255),
    "phone_number" character varying(20),
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "user_id" "uuid",
    "client_type" character varying(20) DEFAULT 'Persona'::character varying NOT NULL
);


ALTER TABLE "public"."clients" OWNER TO "postgres";


COMMENT ON TABLE "public"."clients" IS 'Tabla de clientes asociados a usuarios';



CREATE SEQUENCE IF NOT EXISTS "public"."clients_client_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."clients_client_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."clients_client_id_seq" OWNED BY "public"."clients"."client_id";



CREATE TABLE IF NOT EXISTS "public"."counters" (
    "name" "text" NOT NULL,
    "value" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."counters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_items" (
    "id" integer NOT NULL,
    "group_id" integer NOT NULL,
    "material_id" integer NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."group_items" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."group_items_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."group_items_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."group_items_id_seq" OWNED BY "public"."group_items"."id";



CREATE TABLE IF NOT EXISTS "public"."group_material" (
    "group_id" integer NOT NULL,
    "name" character varying(255) NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "project_id" integer NOT NULL,
    "description" "text",
    "status" character varying(50) DEFAULT 'Activo'::character varying
);


ALTER TABLE "public"."group_material" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."group_material_group_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."group_material_group_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."group_material_group_id_seq" OWNED BY "public"."group_material"."group_id";



CREATE TABLE IF NOT EXISTS "public"."labour" (
    "labour_id" integer NOT NULL,
    "project_id" integer NOT NULL,
    "amount" numeric(15,2) NOT NULL,
    "pay_date" "date" NOT NULL,
    "description" "text",
    "pay_method" character varying(50) DEFAULT 'Efectivo'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "labour_amount_check" CHECK (("amount" > (0)::numeric))
);


ALTER TABLE "public"."labour" OWNER TO "postgres";


COMMENT ON TABLE "public"."labour" IS 'Tabla para registrar abonos de mano de obra por proyecto';



COMMENT ON COLUMN "public"."labour"."labour_id" IS 'Identificador único del abono';



COMMENT ON COLUMN "public"."labour"."project_id" IS 'ID del proyecto al que pertenece el abono';



COMMENT ON COLUMN "public"."labour"."amount" IS 'Monto del abono de mano de obra';



COMMENT ON COLUMN "public"."labour"."pay_date" IS 'Fecha en que se realizó el pago';



COMMENT ON COLUMN "public"."labour"."description" IS 'Descripción opcional del abono';



COMMENT ON COLUMN "public"."labour"."pay_method" IS 'Método de pago (Efectivo, Transferencia, Cheque, etc.)';



COMMENT ON COLUMN "public"."labour"."created_at" IS 'Fecha de creación del registro';



CREATE SEQUENCE IF NOT EXISTS "public"."labour_labour_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."labour_labour_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."labour_labour_id_seq" OWNED BY "public"."labour"."labour_id";



CREATE TABLE IF NOT EXISTS "public"."material" (
    "material_id" integer NOT NULL,
    "name" character varying(255) NOT NULL,
    "price" numeric(15,2),
    "brand" character varying(100),
    "sku" character varying(100),
    "url" "text",
    "urlimg" "text",
    "supplier" character varying(255),
    "category" character varying(100),
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."material" OWNER TO "postgres";


COMMENT ON TABLE "public"."material" IS 'Catálogo de materiales de construcción';



CREATE SEQUENCE IF NOT EXISTS "public"."material_material_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."material_material_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."material_material_id_seq" OWNED BY "public"."material"."material_id";



CREATE TABLE IF NOT EXISTS "public"."payments" (
    "payment_id" integer NOT NULL,
    "project_id" integer NOT NULL,
    "budget_id" integer,
    "rendition_id" integer,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "pay_date" "date" DEFAULT CURRENT_DATE,
    "pay_method" character varying(100),
    "description" "text",
    "amount" numeric(15,2) NOT NULL,
    "payment_type" character varying(50),
    "assignment_id" integer,
    "labour_id" integer
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


COMMENT ON TABLE "public"."payments" IS 'Pagos asociados a presupuestos o rendiciones';



CREATE OR REPLACE VIEW "public"."payment_summary" AS
 SELECT "project_id",
    COALESCE("sum"(
        CASE
            WHEN (("payment_type")::"text" = 'asignacion'::"text") THEN "amount"
            ELSE (0)::numeric
        END), (0)::numeric) AS "total_asignado",
    "count"(
        CASE
            WHEN (("payment_type")::"text" = 'asignacion'::"text") THEN 1
            ELSE NULL::integer
        END) AS "cantidad_asignaciones",
    COALESCE("sum"(
        CASE
            WHEN (("payment_type")::"text" = 'abono_mo'::"text") THEN "amount"
            ELSE (0)::numeric
        END), (0)::numeric) AS "total_abonado",
    "count"(
        CASE
            WHEN (("payment_type")::"text" = 'abono_mo'::"text") THEN 1
            ELSE NULL::integer
        END) AS "cantidad_abonos",
    COALESCE("sum"("amount"), (0)::numeric) AS "total_general",
    "count"(*) AS "total_pagos",
    "min"("created_at") AS "primer_pago",
    "max"("created_at") AS "ultimo_pago"
   FROM "public"."payments" "p"
  GROUP BY "project_id";


ALTER VIEW "public"."payment_summary" OWNER TO "postgres";


COMMENT ON VIEW "public"."payment_summary" IS 'Vista que calcula automáticamente los totales de pagos por proyecto.
Incluye asignaciones y abonos de mano de obra.';



CREATE SEQUENCE IF NOT EXISTS "public"."payments_payment_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."payments_payment_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."payments_payment_id_seq" OWNED BY "public"."payments"."payment_id";



CREATE TABLE IF NOT EXISTS "public"."projects" (
    "project_id" integer NOT NULL,
    "project_name" character varying(255) NOT NULL,
    "quote_number" character varying(100),
    "start_date" "date",
    "status" character varying(50) DEFAULT 'Activo'::character varying,
    "client_id" integer NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "latitude" numeric(9,6),
    "longitude" numeric(9,6)
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


COMMENT ON TABLE "public"."projects" IS 'Tabla de proyectos de construcción';



CREATE SEQUENCE IF NOT EXISTS "public"."projects_project_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."projects_project_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."projects_project_id_seq" OWNED BY "public"."projects"."project_id";



CREATE TABLE IF NOT EXISTS "public"."rendition" (
    "rendition_id" integer NOT NULL,
    "project_id" integer NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "description" "text",
    "total" numeric(15,2) DEFAULT 0
);


ALTER TABLE "public"."rendition" OWNER TO "postgres";


COMMENT ON TABLE "public"."rendition" IS 'Rendiciones de cuentas de proyectos';



CREATE TABLE IF NOT EXISTS "public"."rendition_items" (
    "id" integer NOT NULL,
    "rendition_id" integer NOT NULL,
    "material_id" integer,
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(15,2) NOT NULL,
    "total_price" numeric(15,2) GENERATED ALWAYS AS ((("quantity")::numeric * "unit_price")) STORED,
    "fecha" "date",
    "detalle" "text",
    "proveedor" "text",
    "folio" "text",
    "total" numeric
);


ALTER TABLE "public"."rendition_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."rendition_items" IS 'Ítems detallados de rendiciones';



CREATE SEQUENCE IF NOT EXISTS "public"."rendition_items_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."rendition_items_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."rendition_items_id_seq" OWNED BY "public"."rendition_items"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."rendition_rendition_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."rendition_rendition_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."rendition_rendition_id_seq" OWNED BY "public"."rendition"."rendition_id";



CREATE TABLE IF NOT EXISTS "public"."users" (
    "email" character varying(255) NOT NULL,
    "name" character varying(100) NOT NULL,
    "last_name" character varying(100) NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON TABLE "public"."users" IS 'Tabla de usuarios del sistema';



ALTER TABLE ONLY "public"."assignments" ALTER COLUMN "assignment_id" SET DEFAULT "nextval"('"public"."assignments_assignment_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."attached_group_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."attached_group_items_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."attached_group_material" ALTER COLUMN "group_id" SET DEFAULT "nextval"('"public"."attached_group_material_group_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."budget_items" ALTER COLUMN "item_id" SET DEFAULT "nextval"('"public"."budget_items_item_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."budgets" ALTER COLUMN "budget_id" SET DEFAULT "nextval"('"public"."budgets_budget_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."clients" ALTER COLUMN "client_id" SET DEFAULT "nextval"('"public"."clients_client_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."group_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."group_items_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."group_material" ALTER COLUMN "group_id" SET DEFAULT "nextval"('"public"."group_material_group_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."labour" ALTER COLUMN "labour_id" SET DEFAULT "nextval"('"public"."labour_labour_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."material" ALTER COLUMN "material_id" SET DEFAULT "nextval"('"public"."material_material_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."payments" ALTER COLUMN "payment_id" SET DEFAULT "nextval"('"public"."payments_payment_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."projects" ALTER COLUMN "project_id" SET DEFAULT "nextval"('"public"."projects_project_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."rendition" ALTER COLUMN "rendition_id" SET DEFAULT "nextval"('"public"."rendition_rendition_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."rendition_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."rendition_items_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."assignments"
    ADD CONSTRAINT "assignments_pkey" PRIMARY KEY ("assignment_id");



ALTER TABLE ONLY "public"."attached_group_items"
    ADD CONSTRAINT "attached_group_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attached_group_material"
    ADD CONSTRAINT "attached_group_material_pkey" PRIMARY KEY ("group_id");



ALTER TABLE ONLY "public"."budget_items"
    ADD CONSTRAINT "budget_items_pkey" PRIMARY KEY ("item_id");



ALTER TABLE ONLY "public"."budgets"
    ADD CONSTRAINT "budgets_pkey" PRIMARY KEY ("budget_id");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("client_id");



ALTER TABLE ONLY "public"."counters"
    ADD CONSTRAINT "counters_pkey" PRIMARY KEY ("name");



ALTER TABLE ONLY "public"."group_items"
    ADD CONSTRAINT "group_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_material"
    ADD CONSTRAINT "group_material_pkey" PRIMARY KEY ("group_id");



ALTER TABLE ONLY "public"."labour"
    ADD CONSTRAINT "labour_pkey" PRIMARY KEY ("labour_id");



ALTER TABLE ONLY "public"."material"
    ADD CONSTRAINT "material_pkey" PRIMARY KEY ("material_id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("payment_id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("project_id");



ALTER TABLE ONLY "public"."rendition_items"
    ADD CONSTRAINT "rendition_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rendition"
    ADD CONSTRAINT "rendition_pkey" PRIMARY KEY ("rendition_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("user_id");



CREATE INDEX "idx_assignments_project_id" ON "public"."assignments" USING "btree" ("project_id");



CREATE INDEX "idx_attached_group_project_id" ON "public"."attached_group_material" USING "btree" ("project_id");



CREATE INDEX "idx_attached_items_group_id" ON "public"."attached_group_items" USING "btree" ("group_id");



CREATE INDEX "idx_attached_items_material_id" ON "public"."attached_group_items" USING "btree" ("material_id");



CREATE INDEX "idx_budget_items_budget_id" ON "public"."budget_items" USING "btree" ("budget_id");



CREATE INDEX "idx_budgets_project_id" ON "public"."budgets" USING "btree" ("project_id");



CREATE INDEX "idx_group_items_group_id" ON "public"."group_items" USING "btree" ("group_id");



CREATE INDEX "idx_group_items_material_id" ON "public"."group_items" USING "btree" ("material_id");



CREATE INDEX "idx_group_material_project_id" ON "public"."group_material" USING "btree" ("project_id");



CREATE INDEX "idx_labour_pay_date" ON "public"."labour" USING "btree" ("pay_date" DESC);



CREATE INDEX "idx_labour_project_id" ON "public"."labour" USING "btree" ("project_id");



CREATE INDEX "idx_payments_assignment_id" ON "public"."payments" USING "btree" ("assignment_id");



CREATE INDEX "idx_payments_budget_id" ON "public"."payments" USING "btree" ("budget_id");



CREATE INDEX "idx_payments_labour_id" ON "public"."payments" USING "btree" ("labour_id");



CREATE INDEX "idx_payments_payment_type" ON "public"."payments" USING "btree" ("payment_type");



CREATE INDEX "idx_payments_project_id" ON "public"."payments" USING "btree" ("project_id");



CREATE INDEX "idx_payments_rendition_id" ON "public"."payments" USING "btree" ("rendition_id");



CREATE INDEX "idx_projects_client_id" ON "public"."projects" USING "btree" ("client_id");



CREATE INDEX "idx_rendition_items_material_id" ON "public"."rendition_items" USING "btree" ("material_id");



CREATE INDEX "idx_rendition_items_rendition_id" ON "public"."rendition_items" USING "btree" ("rendition_id");



CREATE INDEX "idx_rendition_project_id" ON "public"."rendition" USING "btree" ("project_id");



CREATE OR REPLACE TRIGGER "trigger_sync_assignment" AFTER INSERT OR DELETE OR UPDATE ON "public"."assignments" FOR EACH ROW EXECUTE FUNCTION "public"."sync_assignment_to_payment"();



CREATE OR REPLACE TRIGGER "trigger_sync_labour" AFTER INSERT OR DELETE OR UPDATE ON "public"."labour" FOR EACH ROW EXECUTE FUNCTION "public"."sync_labour_to_payment"();



ALTER TABLE ONLY "public"."assignments"
    ADD CONSTRAINT "fk_assignments_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attached_group_material"
    ADD CONSTRAINT "fk_attached_group_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attached_group_items"
    ADD CONSTRAINT "fk_attached_items_group" FOREIGN KEY ("group_id") REFERENCES "public"."attached_group_material"("group_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attached_group_items"
    ADD CONSTRAINT "fk_attached_items_material" FOREIGN KEY ("material_id") REFERENCES "public"."material"("material_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."budget_items"
    ADD CONSTRAINT "fk_budget_items_budget" FOREIGN KEY ("budget_id") REFERENCES "public"."budgets"("budget_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."budgets"
    ADD CONSTRAINT "fk_budgets_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "fk_clients_user" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id");



ALTER TABLE ONLY "public"."group_items"
    ADD CONSTRAINT "fk_group_items_group" FOREIGN KEY ("group_id") REFERENCES "public"."group_material"("group_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_items"
    ADD CONSTRAINT "fk_group_items_material" FOREIGN KEY ("material_id") REFERENCES "public"."material"("material_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."group_material"
    ADD CONSTRAINT "fk_group_material_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."labour"
    ADD CONSTRAINT "fk_labour_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "fk_payments_budget" FOREIGN KEY ("budget_id") REFERENCES "public"."budgets"("budget_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "fk_payments_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "fk_payments_rendition" FOREIGN KEY ("rendition_id") REFERENCES "public"."rendition"("rendition_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "fk_projects_client" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rendition_items"
    ADD CONSTRAINT "fk_rendition_items_material" FOREIGN KEY ("material_id") REFERENCES "public"."material"("material_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."rendition_items"
    ADD CONSTRAINT "fk_rendition_items_rendition" FOREIGN KEY ("rendition_id") REFERENCES "public"."rendition"("rendition_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rendition"
    ADD CONSTRAINT "fk_rendition_project" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_assignment_id_fkey" FOREIGN KEY ("assignment_id") REFERENCES "public"."assignments"("assignment_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_labour_id_fkey" FOREIGN KEY ("labour_id") REFERENCES "public"."labour"("labour_id") ON DELETE CASCADE;





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_payment_summary"("p_project_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_counter"("counter_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_counter"("counter_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_counter"("counter_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_assignment_to_payment"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_assignment_to_payment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_assignment_to_payment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_labour_to_payment"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_labour_to_payment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_labour_to_payment"() TO "service_role";


















GRANT ALL ON TABLE "public"."assignments" TO "anon";
GRANT ALL ON TABLE "public"."assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."assignments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."assignments_assignment_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."assignments_assignment_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."assignments_assignment_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."attached_group_items" TO "anon";
GRANT ALL ON TABLE "public"."attached_group_items" TO "authenticated";
GRANT ALL ON TABLE "public"."attached_group_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."attached_group_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."attached_group_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."attached_group_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."attached_group_material" TO "anon";
GRANT ALL ON TABLE "public"."attached_group_material" TO "authenticated";
GRANT ALL ON TABLE "public"."attached_group_material" TO "service_role";



GRANT ALL ON SEQUENCE "public"."attached_group_material_group_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."attached_group_material_group_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."attached_group_material_group_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."budget_items" TO "anon";
GRANT ALL ON TABLE "public"."budget_items" TO "authenticated";
GRANT ALL ON TABLE "public"."budget_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."budget_items_item_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."budget_items_item_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."budget_items_item_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."budgets" TO "anon";
GRANT ALL ON TABLE "public"."budgets" TO "authenticated";
GRANT ALL ON TABLE "public"."budgets" TO "service_role";



GRANT ALL ON SEQUENCE "public"."budgets_budget_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."budgets_budget_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."budgets_budget_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."clients" TO "anon";
GRANT ALL ON TABLE "public"."clients" TO "authenticated";
GRANT ALL ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON SEQUENCE "public"."clients_client_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."clients_client_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."clients_client_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."counters" TO "anon";
GRANT ALL ON TABLE "public"."counters" TO "authenticated";
GRANT ALL ON TABLE "public"."counters" TO "service_role";



GRANT ALL ON TABLE "public"."group_items" TO "anon";
GRANT ALL ON TABLE "public"."group_items" TO "authenticated";
GRANT ALL ON TABLE "public"."group_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."group_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."group_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."group_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."group_material" TO "anon";
GRANT ALL ON TABLE "public"."group_material" TO "authenticated";
GRANT ALL ON TABLE "public"."group_material" TO "service_role";



GRANT ALL ON SEQUENCE "public"."group_material_group_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."group_material_group_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."group_material_group_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."labour" TO "anon";
GRANT ALL ON TABLE "public"."labour" TO "authenticated";
GRANT ALL ON TABLE "public"."labour" TO "service_role";



GRANT ALL ON SEQUENCE "public"."labour_labour_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."labour_labour_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."labour_labour_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."material" TO "anon";
GRANT ALL ON TABLE "public"."material" TO "authenticated";
GRANT ALL ON TABLE "public"."material" TO "service_role";



GRANT ALL ON SEQUENCE "public"."material_material_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."material_material_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."material_material_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "anon";
GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."payment_summary" TO "anon";
GRANT ALL ON TABLE "public"."payment_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_summary" TO "service_role";



GRANT ALL ON SEQUENCE "public"."payments_payment_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."payments_payment_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."payments_payment_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON SEQUENCE "public"."projects_project_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."projects_project_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."projects_project_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."rendition" TO "anon";
GRANT ALL ON TABLE "public"."rendition" TO "authenticated";
GRANT ALL ON TABLE "public"."rendition" TO "service_role";



GRANT ALL ON TABLE "public"."rendition_items" TO "anon";
GRANT ALL ON TABLE "public"."rendition_items" TO "authenticated";
GRANT ALL ON TABLE "public"."rendition_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."rendition_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."rendition_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."rendition_items_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."rendition_rendition_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."rendition_rendition_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."rendition_rendition_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
