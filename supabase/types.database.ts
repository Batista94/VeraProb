export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      asset_status_events: {
        Row: {
          asset_id: string;
          created_at: string;
          id: string;
          new_status: string;
          occurred_at_utc: string;
          organization_id: string;
          previous_status: string;
          reason: string | null;
          triggered_by: string;
        };
        Insert: {
          asset_id: string;
          created_at?: string;
          id?: string;
          new_status: string;
          occurred_at_utc: string;
          organization_id: string;
          previous_status: string;
          reason?: string | null;
          triggered_by: string;
        };
        Update: {
          asset_id?: string;
          created_at?: string;
          id?: string;
          new_status?: string;
          occurred_at_utc?: string;
          organization_id?: string;
          previous_status?: string;
          reason?: string | null;
          triggered_by?: string;
        };
        Relationships: [
          {
            foreignKeyName: "asset_status_events_asset_id_fkey";
            columns: ["asset_id"];
            isOneToOne: false;
            referencedRelation: "vehicles";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_packages: {
        Row: {
          billing_cycle_report_id: string;
          compliance_rate: number;
          contract_id: string | null;
          contractor_cnpj: string | null;
          contractor_id: string | null;
          contractor_name: string;
          created_at: string;
          engine_version_at_gen: string;
          evidence_gap_count: number;
          executed_count: number;
          generated_at_utc: string;
          generated_by_user_id: string;
          hash_algorithm: string;
          id: string;
          lost_revenue_cents: number;
          no_show_count: number;
          organization_id: string;
          package_hash: string | null;
          period_end_utc: string;
          period_start_utc: string;
          previous_package_id: string | null;
          protected_revenue_cents: number;
          report_ledger_boundary: number;
          revenue_at_risk_cents: number;
          schema_version: string;
          snapshot_ids: string[];
          status: string;
          supersession_reason: string | null;
          tenant_cnpj: string | null;
          tenant_name: string;
          total_contracted_revenue_cents: number;
          total_obligations: number;
        };
        Insert: {
          billing_cycle_report_id: string;
          compliance_rate?: number;
          contract_id?: string | null;
          contractor_cnpj?: string | null;
          contractor_id?: string | null;
          contractor_name: string;
          created_at?: string;
          engine_version_at_gen: string;
          evidence_gap_count?: number;
          executed_count?: number;
          generated_at_utc?: string;
          generated_by_user_id: string;
          hash_algorithm?: string;
          id?: string;
          lost_revenue_cents?: number;
          no_show_count?: number;
          organization_id: string;
          package_hash?: string | null;
          period_end_utc: string;
          period_start_utc: string;
          previous_package_id?: string | null;
          protected_revenue_cents?: number;
          report_ledger_boundary: number;
          revenue_at_risk_cents?: number;
          schema_version?: string;
          snapshot_ids: string[];
          status?: string;
          supersession_reason?: string | null;
          tenant_cnpj?: string | null;
          tenant_name: string;
          total_contracted_revenue_cents?: number;
          total_obligations?: number;
        };
        Update: {
          billing_cycle_report_id?: string;
          compliance_rate?: number;
          contract_id?: string | null;
          contractor_cnpj?: string | null;
          contractor_id?: string | null;
          contractor_name?: string;
          created_at?: string;
          engine_version_at_gen?: string;
          evidence_gap_count?: number;
          executed_count?: number;
          generated_at_utc?: string;
          generated_by_user_id?: string;
          hash_algorithm?: string;
          id?: string;
          lost_revenue_cents?: number;
          no_show_count?: number;
          organization_id?: string;
          package_hash?: string | null;
          period_end_utc?: string;
          period_start_utc?: string;
          previous_package_id?: string | null;
          protected_revenue_cents?: number;
          report_ledger_boundary?: number;
          revenue_at_risk_cents?: number;
          schema_version?: string;
          snapshot_ids?: string[];
          status?: string;
          supersession_reason?: string | null;
          tenant_cnpj?: string | null;
          tenant_name?: string;
          total_contracted_revenue_cents?: number;
          total_obligations?: number;
        };
        Relationships: [
          {
            foreignKeyName: "audit_packages_contract_id_fkey";
            columns: ["contract_id"];
            isOneToOne: false;
            referencedRelation: "contracts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_packages_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_packages_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_packages_previous_package_id_fkey";
            columns: ["previous_package_id"];
            isOneToOne: false;
            referencedRelation: "audit_packages";
            referencedColumns: ["id"];
          },
        ];
      };
      canonical_facts: {
        Row: {
          accuracy_meters: number | null;
          asset_id: string | null;
          created_at: string;
          device_id: string;
          gps_timestamp: string;
          heading_degrees: number | null;
          id: string;
          integrity_flag: string;
          lat: number;
          lng: number;
          organization_id: string;
          payload_hmac: string | null;
          raw_payload_id: string;
          received_at_utc: string;
          source_adapter: string;
          speed_cms: number | null;
        };
        Insert: {
          accuracy_meters?: number | null;
          asset_id?: string | null;
          created_at?: string;
          device_id: string;
          gps_timestamp: string;
          heading_degrees?: number | null;
          id?: string;
          integrity_flag?: string;
          lat: number;
          lng: number;
          organization_id: string;
          payload_hmac?: string | null;
          raw_payload_id: string;
          received_at_utc: string;
          source_adapter: string;
          speed_cms?: number | null;
        };
        Update: {
          accuracy_meters?: number | null;
          asset_id?: string | null;
          created_at?: string;
          device_id?: string;
          gps_timestamp?: string;
          heading_degrees?: number | null;
          id?: string;
          integrity_flag?: string;
          lat?: number;
          lng?: number;
          organization_id?: string;
          payload_hmac?: string | null;
          raw_payload_id?: string;
          received_at_utc?: string;
          source_adapter?: string;
          speed_cms?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "canonical_facts_asset_id_fkey";
            columns: ["asset_id"];
            isOneToOne: false;
            referencedRelation: "vehicles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "canonical_facts_raw_payload_id_fkey";
            columns: ["raw_payload_id"];
            isOneToOne: false;
            referencedRelation: "raw_telemetry_payloads";
            referencedColumns: ["id"];
          },
        ];
      };
      contract_review_tokens: {
        Row: {
          contract_id: string;
          created_at_utc: string;
          expires_at_utc: string;
          id: string;
          organization_id: string;
          token: string;
          used_at_utc: string | null;
        };
        Insert: {
          contract_id: string;
          created_at_utc?: string;
          expires_at_utc: string;
          id: string;
          organization_id: string;
          token: string;
          used_at_utc?: string | null;
        };
        Update: {
          contract_id?: string;
          created_at_utc?: string;
          expires_at_utc?: string;
          id?: string;
          organization_id?: string;
          token?: string;
          used_at_utc?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "contract_review_tokens_contract_id_fkey";
            columns: ["contract_id"];
            isOneToOne: false;
            referencedRelation: "contracts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contract_review_tokens_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contract_review_tokens_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contract_review_tokens_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contract_rule_sets: {
        Row: {
          contract_id: string;
          created_at_utc: string;
          id: string;
          organization_id: string;
        };
        Insert: {
          contract_id: string;
          created_at_utc?: string;
          id: string;
          organization_id: string;
        };
        Update: {
          contract_id?: string;
          created_at_utc?: string;
          id?: string;
          organization_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contract_rule_sets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contract_rule_sets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contract_rule_sets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contract_rule_versions: {
        Row: {
          active_from_utc: string;
          active_to_utc: string | null;
          evaluation_order: number;
          id: string;
          rule_config: Json;
          rule_set_id: string;
          rule_type: Database["public"]["Enums"]["sla_rule_type"];
          rule_version: number;
        };
        Insert: {
          active_from_utc?: string;
          active_to_utc?: string | null;
          evaluation_order: number;
          id: string;
          rule_config: Json;
          rule_set_id: string;
          rule_type: Database["public"]["Enums"]["sla_rule_type"];
          rule_version: number;
        };
        Update: {
          active_from_utc?: string;
          active_to_utc?: string | null;
          evaluation_order?: number;
          id?: string;
          rule_config?: Json;
          rule_set_id?: string;
          rule_type?: Database["public"]["Enums"]["sla_rule_type"];
          rule_version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contract_rule_versions_rule_set_id_fkey";
            columns: ["rule_set_id"];
            isOneToOne: false;
            referencedRelation: "contract_rule_sets";
            referencedColumns: ["id"];
          },
        ];
      };
      contractor_justifications: {
        Row: {
          category: string;
          contract_id: string;
          created_at_utc: string;
          description: string;
          id: string;
          organization_id: string;
          resolution_notes: string | null;
          reviewed_at_utc: string | null;
          reviewed_by_user_id: string | null;
          set_id: string;
          status: string;
          submitted_by_token: string | null;
        };
        Insert: {
          category: string;
          contract_id: string;
          created_at_utc?: string;
          description: string;
          id?: string;
          organization_id: string;
          resolution_notes?: string | null;
          reviewed_at_utc?: string | null;
          reviewed_by_user_id?: string | null;
          set_id: string;
          status?: string;
          submitted_by_token?: string | null;
        };
        Update: {
          category?: string;
          contract_id?: string;
          created_at_utc?: string;
          description?: string;
          id?: string;
          organization_id?: string;
          resolution_notes?: string | null;
          reviewed_at_utc?: string | null;
          reviewed_by_user_id?: string | null;
          set_id?: string;
          status?: string;
          submitted_by_token?: string | null;
        };
        Relationships: [];
      };
      contractors: {
        Row: {
          contact_name: string;
          created_at_utc: string;
          external_id: string | null;
          id: string;
          name: string;
          organization_id: string;
          primary_email: string;
          tax_id: string;
        };
        Insert: {
          contact_name: string;
          created_at_utc?: string;
          external_id?: string | null;
          id?: string;
          name: string;
          organization_id: string;
          primary_email: string;
          tax_id: string;
        };
        Update: {
          contact_name?: string;
          created_at_utc?: string;
          external_id?: string | null;
          id?: string;
          name?: string;
          organization_id?: string;
          primary_email?: string;
          tax_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contracts: {
        Row: {
          activated_at_utc: string | null;
          cloned_from_contract_id: string | null;
          close_reason: string | null;
          closed_at_utc: string | null;
          closed_by_user_id: string | null;
          contractor_id: string | null;
          contractor_name: string;
          created_at_utc: string;
          current_hash: string | null;
          description: string | null;
          external_id: string | null;
          financial_ceiling_cents: number | null;
          id: string;
          latitude: number | null;
          longitude: number | null;
          name: string;
          notes: string | null;
          organization_id: string;
          penalty_multiplier: number;
          previous_hash: string | null;
          status: string;
          submitted_for_approval_at_utc: string | null;
          valid_from_utc: string;
          valid_until_utc: string;
          version: number;
        };
        Insert: {
          activated_at_utc?: string | null;
          cloned_from_contract_id?: string | null;
          close_reason?: string | null;
          closed_at_utc?: string | null;
          closed_by_user_id?: string | null;
          contractor_id?: string | null;
          contractor_name: string;
          created_at_utc?: string;
          current_hash?: string | null;
          description?: string | null;
          external_id?: string | null;
          financial_ceiling_cents?: number | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          name: string;
          notes?: string | null;
          organization_id: string;
          penalty_multiplier?: number;
          previous_hash?: string | null;
          status?: string;
          submitted_for_approval_at_utc?: string | null;
          valid_from_utc: string;
          valid_until_utc: string;
          version?: number;
        };
        Update: {
          activated_at_utc?: string | null;
          cloned_from_contract_id?: string | null;
          close_reason?: string | null;
          closed_at_utc?: string | null;
          closed_by_user_id?: string | null;
          contractor_id?: string | null;
          contractor_name?: string;
          created_at_utc?: string;
          current_hash?: string | null;
          description?: string | null;
          external_id?: string | null;
          financial_ceiling_cents?: number | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          name?: string;
          notes?: string | null;
          organization_id?: string;
          penalty_multiplier?: number;
          previous_hash?: string | null;
          status?: string;
          submitted_for_approval_at_utc?: string | null;
          valid_from_utc?: string;
          valid_until_utc?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contracts_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contracts_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contracts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contracts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contracts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contractual_evaluation_traces: {
        Row: {
          decisions_jsonb: Json;
          engine_version: string;
          entity_id: string;
          evaluated_at_utc: string;
          id: string;
          organization_id: string;
          triggering_event_id: string;
        };
        Insert: {
          decisions_jsonb?: Json;
          engine_version: string;
          entity_id: string;
          evaluated_at_utc?: string;
          id?: string;
          organization_id: string;
          triggering_event_id: string;
        };
        Update: {
          decisions_jsonb?: Json;
          engine_version?: string;
          entity_id?: string;
          evaluated_at_utc?: string;
          id?: string;
          organization_id?: string;
          triggering_event_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contractual_evaluation_traces_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_evaluation_traces_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_evaluation_traces_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contractual_financial_snapshot: {
        Row: {
          author_user_id: string | null;
          closed_at_utc: string;
          contract_id: string | null;
          created_at: string;
          engine_version: string;
          evidence_gap_count: number;
          executed_count: number;
          id: string;
          last_ledger_entry_id: number | null;
          last_ledger_entry_uuid: string | null;
          loss_percentage: number | null;
          loss_percentage_bps: number;
          lost_revenue_cents: number;
          no_show_count: number;
          operational_date_utc: string;
          operational_timezone: string;
          organization_id: string;
          previous_snapshot_id: string | null;
          protected_revenue_cents: number;
          reprocessing_reason: string | null;
          revenue_at_risk_cents: number;
          risk_percentage: number | null;
          risk_percentage_bps: number;
          total_contracted_revenue_cents: number;
          total_obligations: number;
          updated_at: string;
        };
        Insert: {
          author_user_id?: string | null;
          closed_at_utc: string;
          contract_id?: string | null;
          created_at?: string;
          engine_version: string;
          evidence_gap_count?: number;
          executed_count?: number;
          id: string;
          last_ledger_entry_id?: number | null;
          last_ledger_entry_uuid?: string | null;
          loss_percentage?: number | null;
          loss_percentage_bps: number;
          lost_revenue_cents: number;
          no_show_count?: number;
          operational_date_utc: string;
          operational_timezone: string;
          organization_id?: string;
          previous_snapshot_id?: string | null;
          protected_revenue_cents: number;
          reprocessing_reason?: string | null;
          revenue_at_risk_cents: number;
          risk_percentage?: number | null;
          risk_percentage_bps: number;
          total_contracted_revenue_cents: number;
          total_obligations?: number;
          updated_at?: string;
        };
        Update: {
          author_user_id?: string | null;
          closed_at_utc?: string;
          contract_id?: string | null;
          created_at?: string;
          engine_version?: string;
          evidence_gap_count?: number;
          executed_count?: number;
          id?: string;
          last_ledger_entry_id?: number | null;
          last_ledger_entry_uuid?: string | null;
          loss_percentage?: number | null;
          loss_percentage_bps?: number;
          lost_revenue_cents?: number;
          no_show_count?: number;
          operational_date_utc?: string;
          operational_timezone?: string;
          organization_id?: string;
          previous_snapshot_id?: string | null;
          protected_revenue_cents?: number;
          reprocessing_reason?: string | null;
          revenue_at_risk_cents?: number;
          risk_percentage?: number | null;
          risk_percentage_bps?: number;
          total_contracted_revenue_cents?: number;
          total_obligations?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contractual_financial_snapshot_last_ledger_entry_id_fkey";
            columns: ["last_ledger_entry_id"];
            isOneToOne: false;
            referencedRelation: "sla_audit_ledger";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_financial_snapshot_previous_snapshot_id_fkey";
            columns: ["previous_snapshot_id"];
            isOneToOne: false;
            referencedRelation: "contractual_financial_snapshot";
            referencedColumns: ["id"];
          },
        ];
      };
      contractual_financial_snapshot_v2: {
        Row: {
          created_at: string;
          organization_id: string;
          total_fines_cents: number;
          trip_id: string;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          organization_id: string;
          total_fines_cents?: number;
          trip_id: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          organization_id?: string;
          total_fines_cents?: number;
          trip_id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "contractual_financial_snapshot_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_financial_snapshot_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_financial_snapshot_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      contractual_service_executions: {
        Row: {
          contractual_value_cents: number;
          delay_penalty_per_minute_cents: number | null;
          delay_tolerance_minutes: number | null;
          destination_zone_id: string | null;
          downgrade_penalty_flat_cents: number | null;
          end_latitude: number;
          end_longitude: number;
          end_radius_meters: number;
          no_show_penalty_multiplier: number;
          operational_date: string | null;
          organization_id: string | null;
          origin_zone_id: string | null;
          plan_declaration_id: string;
          planned_vehicle_id: string | null;
          scheduled_end_time_utc: string;
          scheduled_start_time_utc: string;
          set_id: string;
          shift_pattern_index: number | null;
          start_latitude: number;
          start_longitude: number;
          start_radius_meters: number;
        };
        Insert: {
          contractual_value_cents: number;
          delay_penalty_per_minute_cents?: number | null;
          delay_tolerance_minutes?: number | null;
          destination_zone_id?: string | null;
          downgrade_penalty_flat_cents?: number | null;
          end_latitude: number;
          end_longitude: number;
          end_radius_meters: number;
          no_show_penalty_multiplier: number;
          operational_date?: string | null;
          organization_id?: string | null;
          origin_zone_id?: string | null;
          plan_declaration_id: string;
          planned_vehicle_id?: string | null;
          scheduled_end_time_utc: string;
          scheduled_start_time_utc: string;
          set_id: string;
          shift_pattern_index?: number | null;
          start_latitude: number;
          start_longitude: number;
          start_radius_meters: number;
        };
        Update: {
          contractual_value_cents?: number;
          delay_penalty_per_minute_cents?: number | null;
          delay_tolerance_minutes?: number | null;
          destination_zone_id?: string | null;
          downgrade_penalty_flat_cents?: number | null;
          end_latitude?: number;
          end_longitude?: number;
          end_radius_meters?: number;
          no_show_penalty_multiplier?: number;
          operational_date?: string | null;
          organization_id?: string | null;
          origin_zone_id?: string | null;
          plan_declaration_id?: string;
          planned_vehicle_id?: string | null;
          scheduled_end_time_utc?: string;
          scheduled_start_time_utc?: string;
          set_id?: string;
          shift_pattern_index?: number | null;
          start_latitude?: number;
          start_longitude?: number;
          start_radius_meters?: number;
        };
        Relationships: [
          {
            foreignKeyName: "contractual_service_executions_destination_zone_id_fkey";
            columns: ["destination_zone_id"];
            isOneToOne: false;
            referencedRelation: "operational_zones";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_service_executions_origin_zone_id_fkey";
            columns: ["origin_zone_id"];
            isOneToOne: false;
            referencedRelation: "operational_zones";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractual_service_executions_plan_declaration_id_fkey";
            columns: ["plan_declaration_id"];
            isOneToOne: false;
            referencedRelation: "plan_declarations";
            referencedColumns: ["id"];
          },
        ];
      };
      csv_mapping_templates: {
        Row: {
          column_mappings: Json;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          id: string;
          is_default: boolean;
          name: string;
          organization_id: string;
          target_entity: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          column_mappings?: Json;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          id?: string;
          is_default?: boolean;
          name: string;
          organization_id: string;
          target_entity: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          column_mappings?: Json;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          id?: string;
          is_default?: boolean;
          name?: string;
          organization_id?: string;
          target_entity?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [];
      };
      drivers: {
        Row: {
          archived_at_utc: string | null;
          cpf: string | null;
          created_at: string | null;
          external_id: string | null;
          full_name: string;
          id: string;
          license_category: string | null;
          license_expiry_utc: string | null;
          license_number: string;
          organization_id: string | null;
          phone: string | null;
          status: string | null;
          updated_at: string | null;
        };
        Insert: {
          archived_at_utc?: string | null;
          cpf?: string | null;
          created_at?: string | null;
          external_id?: string | null;
          full_name: string;
          id?: string;
          license_category?: string | null;
          license_expiry_utc?: string | null;
          license_number: string;
          organization_id?: string | null;
          phone?: string | null;
          status?: string | null;
          updated_at?: string | null;
        };
        Update: {
          archived_at_utc?: string | null;
          cpf?: string | null;
          created_at?: string | null;
          external_id?: string | null;
          full_name?: string;
          id?: string;
          license_category?: string | null;
          license_expiry_utc?: string | null;
          license_number?: string;
          organization_id?: string | null;
          phone?: string | null;
          status?: string | null;
          updated_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "fk_drivers_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_drivers_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_drivers_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      evidence_deletion_queue: {
        Row: {
          delete_after_utc: string;
          deleted_at: string | null;
          evidence_url: string;
          id: string;
          justification_id: string;
          marked_at_utc: string;
          organization_id: string;
        };
        Insert: {
          delete_after_utc: string;
          deleted_at?: string | null;
          evidence_url: string;
          id?: string;
          justification_id: string;
          marked_at_utc?: string;
          organization_id: string;
        };
        Update: {
          delete_after_utc?: string;
          deleted_at?: string | null;
          evidence_url?: string;
          id?: string;
          justification_id?: string;
          marked_at_utc?: string;
          organization_id?: string;
        };
        Relationships: [];
      };
      execution_state_transitions: {
        Row: {
          execution_state_id: string;
          id: number;
          metadata: Json | null;
          new_status: string;
          organization_id: string | null;
          previous_status: string | null;
          reason: string;
          transitioned_at_utc: string;
        };
        Insert: {
          execution_state_id: string;
          id?: never;
          metadata?: Json | null;
          new_status: string;
          organization_id?: string | null;
          previous_status?: string | null;
          reason: string;
          transitioned_at_utc: string;
        };
        Update: {
          execution_state_id?: string;
          id?: never;
          metadata?: Json | null;
          new_status?: string;
          organization_id?: string | null;
          previous_status?: string | null;
          reason?: string;
          transitioned_at_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "execution_state_transitions_execution_state_id_fkey";
            columns: ["execution_state_id"];
            isOneToOne: false;
            referencedRelation: "execution_states";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "execution_state_transitions_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "execution_state_transitions_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "execution_state_transitions_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      execution_states: {
        Row: {
          binding_latitude: number | null;
          binding_longitude: number | null;
          binding_timestamp_utc: string | null;
          bound_operator_id: string | null;
          bound_vehicle_id: string | null;
          contract_id: string;
          contractual_value_cents: number;
          created_at_utc: string;
          destination_zone_entered_at_utc: string | null;
          finalized_at_utc: string | null;
          id: string;
          last_evaluated_at_utc: string;
          no_show_penalty_multiplier: number;
          organization_id: string | null;
          plan_version: number;
          planned_vehicle_id: string | null;
          set_id: string;
          start_latitude: number;
          start_longitude: number;
          start_radius_meters: number;
          status: string;
          status_last_updated_at_utc: string;
          window_end_utc: string;
          window_start_utc: string;
        };
        Insert: {
          binding_latitude?: number | null;
          binding_longitude?: number | null;
          binding_timestamp_utc?: string | null;
          bound_operator_id?: string | null;
          bound_vehicle_id?: string | null;
          contract_id: string;
          contractual_value_cents: number;
          created_at_utc: string;
          destination_zone_entered_at_utc?: string | null;
          finalized_at_utc?: string | null;
          id: string;
          last_evaluated_at_utc: string;
          no_show_penalty_multiplier: number;
          organization_id?: string | null;
          plan_version: number;
          planned_vehicle_id?: string | null;
          set_id: string;
          start_latitude: number;
          start_longitude: number;
          start_radius_meters: number;
          status: string;
          status_last_updated_at_utc: string;
          window_end_utc: string;
          window_start_utc: string;
        };
        Update: {
          binding_latitude?: number | null;
          binding_longitude?: number | null;
          binding_timestamp_utc?: string | null;
          bound_operator_id?: string | null;
          bound_vehicle_id?: string | null;
          contract_id?: string;
          contractual_value_cents?: number;
          created_at_utc?: string;
          destination_zone_entered_at_utc?: string | null;
          finalized_at_utc?: string | null;
          id?: string;
          last_evaluated_at_utc?: string;
          no_show_penalty_multiplier?: number;
          organization_id?: string | null;
          plan_version?: number;
          planned_vehicle_id?: string | null;
          set_id?: string;
          start_latitude?: number;
          start_longitude?: number;
          start_radius_meters?: number;
          status?: string;
          status_last_updated_at_utc?: string;
          window_end_utc?: string;
          window_start_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "execution_states_bound_operator_id_fkey";
            columns: ["bound_operator_id"];
            isOneToOne: false;
            referencedRelation: "drivers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "execution_states_set_id_fkey";
            columns: ["set_id"];
            isOneToOne: true;
            referencedRelation: "contractual_service_executions";
            referencedColumns: ["set_id"];
          },
        ];
      };
      forensic_evidence_snapshots: {
        Row: {
          contract_id: string;
          effective_from_utc: string | null;
          effective_to_utc: string | null;
          id: string;
          idempotency_key: string;
          integrity_hash: string;
          ledger_entry_id: string;
          organization_id: string;
          rule_set_id: string;
          schema_version: number;
          sealed_at_utc: string;
          sealed_by: string;
          sla_rule_version: number;
          snapshot: Json;
        };
        Insert: {
          contract_id: string;
          effective_from_utc?: string | null;
          effective_to_utc?: string | null;
          id?: string;
          idempotency_key: string;
          integrity_hash: string;
          ledger_entry_id: string;
          organization_id: string;
          rule_set_id: string;
          schema_version?: number;
          sealed_at_utc?: string;
          sealed_by: string;
          sla_rule_version: number;
          snapshot: Json;
        };
        Update: {
          contract_id?: string;
          effective_from_utc?: string | null;
          effective_to_utc?: string | null;
          id?: string;
          idempotency_key?: string;
          integrity_hash?: string;
          ledger_entry_id?: string;
          organization_id?: string;
          rule_set_id?: string;
          schema_version?: number;
          sealed_at_utc?: string;
          sealed_by?: string;
          sla_rule_version?: number;
          snapshot?: Json;
        };
        Relationships: [
          {
            foreignKeyName: "fk_fes_ledger_entry";
            columns: ["organization_id", "ledger_entry_id"];
            isOneToOne: true;
            referencedRelation: "sla_audit_ledger_v2";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "forensic_evidence_snapshots_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "forensic_evidence_snapshots_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "forensic_evidence_snapshots_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      forensic_throttle_events: {
        Row: {
          event_type: string;
          id: string;
          metadata: Json | null;
          occurred_at: string;
          organization_id: string;
          user_id: string;
        };
        Insert: {
          event_type: string;
          id?: string;
          metadata?: Json | null;
          occurred_at?: string;
          organization_id: string;
          user_id: string;
        };
        Update: {
          event_type?: string;
          id?: string;
          metadata?: Json | null;
          occurred_at?: string;
          organization_id?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      forensic_throttle_state: {
        Row: {
          consecutive_failures: number;
          next_allowed_at: string;
          organization_id: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          consecutive_failures?: number;
          next_allowed_at?: string;
          organization_id: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          consecutive_failures?: number;
          next_allowed_at?: string;
          organization_id?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      idempotency_keys: {
        Row: {
          command_path: string;
          completed_at_utc: string | null;
          created_at_utc: string;
          id: string;
          organization_id: string;
          response_body: Json | null;
          response_code: number | null;
          stale_threshold_minutes: number;
          status: string;
          user_id: string;
        };
        Insert: {
          command_path: string;
          completed_at_utc?: string | null;
          created_at_utc?: string;
          id: string;
          organization_id: string;
          response_body?: Json | null;
          response_code?: number | null;
          stale_threshold_minutes?: number;
          status: string;
          user_id: string;
        };
        Update: {
          command_path?: string;
          completed_at_utc?: string | null;
          created_at_utc?: string;
          id?: string;
          organization_id?: string;
          response_body?: Json | null;
          response_code?: number | null;
          stale_threshold_minutes?: number;
          status?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      impersonation_sessions: {
        Row: {
          expires_at: string;
          id: string;
          impersonator_user_id: string;
          issued_at: string;
          revocation_reason: string | null;
          revoked_at: string | null;
          target_org_id: string;
          target_user_id: string | null;
          ticket_id: string;
        };
        Insert: {
          expires_at: string;
          id?: string;
          impersonator_user_id: string;
          issued_at?: string;
          revocation_reason?: string | null;
          revoked_at?: string | null;
          target_org_id: string;
          target_user_id?: string | null;
          ticket_id: string;
        };
        Update: {
          expires_at?: string;
          id?: string;
          impersonator_user_id?: string;
          issued_at?: string;
          revocation_reason?: string | null;
          revoked_at?: string | null;
          target_org_id?: string;
          target_user_id?: string | null;
          ticket_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "impersonation_sessions_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "impersonation_sessions_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "impersonation_sessions_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      ingestion_alerts: {
        Row: {
          acknowledged_at_utc: string | null;
          alert_type: string;
          created_at_utc: string;
          detail: string | null;
          device_serial: string | null;
          id: string;
          organization_id: string;
        };
        Insert: {
          acknowledged_at_utc?: string | null;
          alert_type: string;
          created_at_utc?: string;
          detail?: string | null;
          device_serial?: string | null;
          id?: string;
          organization_id: string;
        };
        Update: {
          acknowledged_at_utc?: string | null;
          alert_type?: string;
          created_at_utc?: string;
          detail?: string | null;
          device_serial?: string | null;
          id?: string;
          organization_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "ingestion_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "ingestion_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "ingestion_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      invitations: {
        Row: {
          accepted_at_utc: string | null;
          created_at_utc: string;
          email: string;
          expires_at_utc: string;
          id: string;
          invited_by: string;
          organization_id: string;
          revoked_at_utc: string | null;
          role: string;
          token: string;
        };
        Insert: {
          accepted_at_utc?: string | null;
          created_at_utc?: string;
          email: string;
          expires_at_utc?: string;
          id?: string;
          invited_by: string;
          organization_id: string;
          revoked_at_utc?: string | null;
          role: string;
          token: string;
        };
        Update: {
          accepted_at_utc?: string | null;
          created_at_utc?: string;
          email?: string;
          expires_at_utc?: string;
          id?: string;
          invited_by?: string;
          organization_id?: string;
          revoked_at_utc?: string | null;
          role?: string;
          token?: string;
        };
        Relationships: [
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      justification_audit_logs: {
        Row: {
          caller_role: string;
          id: string;
          justification_id: string;
          new_status: string;
          organization_id: string;
          previous_status: string;
          timestamp_utc: string;
          user_id: string;
        };
        Insert: {
          caller_role: string;
          id?: string;
          justification_id: string;
          new_status: string;
          organization_id: string;
          previous_status: string;
          timestamp_utc?: string;
          user_id: string;
        };
        Update: {
          caller_role?: string;
          id?: string;
          justification_id?: string;
          new_status?: string;
          organization_id?: string;
          previous_status?: string;
          timestamp_utc?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      justification_evidence_uploads: {
        Row: {
          content_hash: string;
          file_name: string;
          id: string;
          justification_id: string;
          organization_id: string;
          storage_path: string;
          uploaded_at_utc: string;
        };
        Insert: {
          content_hash: string;
          file_name: string;
          id?: string;
          justification_id: string;
          organization_id: string;
          storage_path: string;
          uploaded_at_utc?: string;
        };
        Update: {
          content_hash?: string;
          file_name?: string;
          id?: string;
          justification_id?: string;
          organization_id?: string;
          storage_path?: string;
          uploaded_at_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "justification_evidence_uploads_justification_id_fkey";
            columns: ["justification_id"];
            isOneToOne: false;
            referencedRelation: "contractor_justifications";
            referencedColumns: ["id"];
          },
        ];
      };
      justification_recomputation_signals: {
        Row: {
          contract_id: string;
          id: string;
          justification_id: string;
          organization_id: string;
          resolved_at_utc: string | null;
          set_id: string;
          signaled_at_utc: string;
        };
        Insert: {
          contract_id: string;
          id?: string;
          justification_id: string;
          organization_id: string;
          resolved_at_utc?: string | null;
          set_id: string;
          signaled_at_utc?: string;
        };
        Update: {
          contract_id?: string;
          id?: string;
          justification_id?: string;
          organization_id?: string;
          resolved_at_utc?: string | null;
          set_id?: string;
          signaled_at_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "justification_recomputation_signals_justification_id_fkey";
            columns: ["justification_id"];
            isOneToOne: false;
            referencedRelation: "contractor_justifications";
            referencedColumns: ["id"];
          },
        ];
      };
      justification_submission_tokens: {
        Row: {
          contract_id: string;
          created_at_utc: string;
          created_by_user_id: string;
          expires_at_utc: string;
          id: string;
          justification_id: string | null;
          organization_id: string;
          set_id: string;
          token: string;
          used_at_utc: string | null;
        };
        Insert: {
          contract_id: string;
          created_at_utc?: string;
          created_by_user_id: string;
          expires_at_utc: string;
          id?: string;
          justification_id?: string | null;
          organization_id: string;
          set_id: string;
          token?: string;
          used_at_utc?: string | null;
        };
        Update: {
          contract_id?: string;
          created_at_utc?: string;
          created_by_user_id?: string;
          expires_at_utc?: string;
          id?: string;
          justification_id?: string | null;
          organization_id?: string;
          set_id?: string;
          token?: string;
          used_at_utc?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "justification_submission_tokens_justification_id_fkey";
            columns: ["justification_id"];
            isOneToOne: false;
            referencedRelation: "contractor_justifications";
            referencedColumns: ["id"];
          },
        ];
      };
      operational_alerts: {
        Row: {
          acknowledged_at_utc: string | null;
          acknowledged_by_user_id: string | null;
          alert_type: string;
          context: Json;
          contract_id: string;
          entity_id: string;
          id: string;
          organization_id: string;
          resolved_at_utc: string | null;
          severity: string;
          source: string;
          status: string;
          trace_id: string | null;
          triggered_at_utc: string;
          triggering_event_id: string | null;
          viewed_by_user_ids: string[];
        };
        Insert: {
          acknowledged_at_utc?: string | null;
          acknowledged_by_user_id?: string | null;
          alert_type: string;
          context?: Json;
          contract_id: string;
          entity_id: string;
          id?: string;
          organization_id: string;
          resolved_at_utc?: string | null;
          severity: string;
          source?: string;
          status?: string;
          trace_id?: string | null;
          triggered_at_utc?: string;
          triggering_event_id?: string | null;
          viewed_by_user_ids?: string[];
        };
        Update: {
          acknowledged_at_utc?: string | null;
          acknowledged_by_user_id?: string | null;
          alert_type?: string;
          context?: Json;
          contract_id?: string;
          entity_id?: string;
          id?: string;
          organization_id?: string;
          resolved_at_utc?: string | null;
          severity?: string;
          source?: string;
          status?: string;
          trace_id?: string | null;
          triggered_at_utc?: string;
          triggering_event_id?: string | null;
          viewed_by_user_ids?: string[];
        };
        Relationships: [
          {
            foreignKeyName: "operational_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_alerts_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_alerts_trace_id_fkey";
            columns: ["trace_id"];
            isOneToOne: false;
            referencedRelation: "contractual_evaluation_traces";
            referencedColumns: ["id"];
          },
        ];
      };
      operational_zones: {
        Row: {
          address: string | null;
          contractor_id: string | null;
          contractor_label: string | null;
          created_at: string;
          created_at_utc: string;
          external_id: string | null;
          id: string;
          latitude: number | null;
          longitude: number | null;
          name: string;
          organization_id: string;
          radius_meters: number | null;
          type: string;
          zone_scope: string | null;
        };
        Insert: {
          address?: string | null;
          contractor_id?: string | null;
          contractor_label?: string | null;
          created_at?: string;
          created_at_utc?: string;
          external_id?: string | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          name: string;
          organization_id: string;
          radius_meters?: number | null;
          type?: string;
          zone_scope?: string | null;
        };
        Update: {
          address?: string | null;
          contractor_id?: string | null;
          contractor_label?: string | null;
          created_at?: string;
          created_at_utc?: string;
          external_id?: string | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          name?: string;
          organization_id?: string;
          radius_meters?: number | null;
          type?: string;
          zone_scope?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "operational_zones_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_zones_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_zones_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_zones_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "operational_zones_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      org_api_secrets: {
        Row: {
          created_at: string;
          id: string;
          organization_id: string;
          revoked_at: string | null;
          rotated_at: string | null;
          secret_hash: string;
          version: number;
        };
        Insert: {
          created_at?: string;
          id?: string;
          organization_id: string;
          revoked_at?: string | null;
          rotated_at?: string | null;
          secret_hash: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          id?: string;
          organization_id?: string;
          revoked_at?: string | null;
          rotated_at?: string | null;
          secret_hash?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "org_api_secrets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "org_api_secrets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "org_api_secrets_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      org_quota_warnings: {
        Row: {
          current_count: number;
          id: number;
          max_allowed: number;
          organization_id: string;
          resolved_at: string | null;
          resource: string;
          threshold: number;
          triggered_at: string;
          usage_pct: number;
        };
        Insert: {
          current_count: number;
          id?: never;
          max_allowed: number;
          organization_id: string;
          resolved_at?: string | null;
          resource: string;
          threshold: number;
          triggered_at?: string;
          usage_pct: number;
        };
        Update: {
          current_count?: number;
          id?: never;
          max_allowed?: number;
          organization_id?: string;
          resolved_at?: string | null;
          resource?: string;
          threshold?: number;
          triggered_at?: string;
          usage_pct?: number;
        };
        Relationships: [
          {
            foreignKeyName: "org_quota_warnings_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "org_quota_warnings_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "org_quota_warnings_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      organizations: {
        Row: {
          allowed_domains: string[];
          billing_day: number | null;
          capabilities: Json;
          clock_drift_tolerance_s: number;
          cnpj: string | null;
          connection_pool_limit: number;
          contact_email: string | null;
          created_at: string;
          currency_code: string | null;
          data_retention_days: number;
          dwell_time_seconds: number;
          external_id: string | null;
          id: string;
          is_active: boolean | null;
          last_schema_check_at: string | null;
          legal_name: string | null;
          logo_url: string | null;
          max_active_contracts: number | null;
          max_vehicles: number | null;
          name: string;
          organization_type: string | null;
          plan_type: string;
          schema_integrity_status: string;
          schema_version: string;
          status: string;
          storage_quota_gb: number;
          timezone: string | null;
          tool_cost_cents: number | null;
          updated_at: string | null;
        };
        Insert: {
          allowed_domains?: string[];
          billing_day?: number | null;
          capabilities?: Json;
          clock_drift_tolerance_s?: number;
          cnpj?: string | null;
          connection_pool_limit?: number;
          contact_email?: string | null;
          created_at?: string;
          currency_code?: string | null;
          data_retention_days?: number;
          dwell_time_seconds?: number;
          external_id?: string | null;
          id?: string;
          is_active?: boolean | null;
          last_schema_check_at?: string | null;
          legal_name?: string | null;
          logo_url?: string | null;
          max_active_contracts?: number | null;
          max_vehicles?: number | null;
          name: string;
          organization_type?: string | null;
          plan_type?: string;
          schema_integrity_status?: string;
          schema_version?: string;
          status?: string;
          storage_quota_gb?: number;
          timezone?: string | null;
          tool_cost_cents?: number | null;
          updated_at?: string | null;
        };
        Update: {
          allowed_domains?: string[];
          billing_day?: number | null;
          capabilities?: Json;
          clock_drift_tolerance_s?: number;
          cnpj?: string | null;
          connection_pool_limit?: number;
          contact_email?: string | null;
          created_at?: string;
          currency_code?: string | null;
          data_retention_days?: number;
          dwell_time_seconds?: number;
          external_id?: string | null;
          id?: string;
          is_active?: boolean | null;
          last_schema_check_at?: string | null;
          legal_name?: string | null;
          logo_url?: string | null;
          max_active_contracts?: number | null;
          max_vehicles?: number | null;
          name?: string;
          organization_type?: string | null;
          plan_type?: string;
          schema_integrity_status?: string;
          schema_version?: string;
          status?: string;
          storage_quota_gb?: number;
          timezone?: string | null;
          tool_cost_cents?: number | null;
          updated_at?: string | null;
        };
        Relationships: [];
      };
      pdf_dossier_logs: {
        Row: {
          document_hash_sha256: string;
          generated_at: string;
          generated_by: string;
          id: string;
          organization_id: string;
          sla_ledger_entry_id: string;
        };
        Insert: {
          document_hash_sha256: string;
          generated_at?: string;
          generated_by: string;
          id?: string;
          organization_id: string;
          sla_ledger_entry_id: string;
        };
        Update: {
          document_hash_sha256?: string;
          generated_at?: string;
          generated_by?: string;
          id?: string;
          organization_id?: string;
          sla_ledger_entry_id?: string;
        };
        Relationships: [];
      };
      plan_declarations: {
        Row: {
          contract_fk: string | null;
          contract_id: string;
          current_hash: string | null;
          declared_at_utc: string;
          declared_by_user_id: string;
          id: string;
          organization_id: string | null;
          original_file_hash: string;
          plan_version: number;
          previous_hash: string | null;
          rule_snapshot_jsonb: Json | null;
          shift_patterns_payload: Json | null;
        };
        Insert: {
          contract_fk?: string | null;
          contract_id: string;
          current_hash?: string | null;
          declared_at_utc: string;
          declared_by_user_id: string;
          id: string;
          organization_id?: string | null;
          original_file_hash: string;
          plan_version: number;
          previous_hash?: string | null;
          rule_snapshot_jsonb?: Json | null;
          shift_patterns_payload?: Json | null;
        };
        Update: {
          contract_fk?: string | null;
          contract_id?: string;
          current_hash?: string | null;
          declared_at_utc?: string;
          declared_by_user_id?: string;
          id?: string;
          organization_id?: string | null;
          original_file_hash?: string;
          plan_version?: number;
          previous_hash?: string | null;
          rule_snapshot_jsonb?: Json | null;
          shift_patterns_payload?: Json | null;
        };
        Relationships: [
          {
            foreignKeyName: "plan_declarations_contract_fk_fkey";
            columns: ["contract_fk"];
            isOneToOne: false;
            referencedRelation: "contracts";
            referencedColumns: ["id"];
          },
        ];
      };
      provider_api_keys: {
        Row: {
          api_key_hash: string;
          created_at: string;
          description: string | null;
          id: string;
          is_active: boolean;
          organization_id: string;
          provider_name: string;
        };
        Insert: {
          api_key_hash: string;
          created_at?: string;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          organization_id: string;
          provider_name: string;
        };
        Update: {
          api_key_hash?: string;
          created_at?: string;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          organization_id?: string;
          provider_name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "provider_api_keys_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "provider_api_keys_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "provider_api_keys_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      raw_telemetry_payloads: {
        Row: {
          created_at: string;
          device_id: string;
          id: string;
          organization_id: string;
          payload_hash: string;
          provider_name: string;
          raw_payload: Json;
          received_at_utc: string;
        };
        Insert: {
          created_at?: string;
          device_id: string;
          id?: string;
          organization_id: string;
          payload_hash: string;
          provider_name: string;
          raw_payload: Json;
          received_at_utc?: string;
        };
        Update: {
          created_at?: string;
          device_id?: string;
          id?: string;
          organization_id?: string;
          payload_hash?: string;
          provider_name?: string;
          raw_payload?: Json;
          received_at_utc?: string;
        };
        Relationships: [];
      };
      routes: {
        Row: {
          agency_id: string | null;
          color: string | null;
          created_at: string | null;
          gtfs_route_id: string | null;
          id: string;
          long_name: string | null;
          organization_id: string | null;
          short_name: string | null;
        };
        Insert: {
          agency_id?: string | null;
          color?: string | null;
          created_at?: string | null;
          gtfs_route_id?: string | null;
          id?: string;
          long_name?: string | null;
          organization_id?: string | null;
          short_name?: string | null;
        };
        Update: {
          agency_id?: string | null;
          color?: string | null;
          created_at?: string | null;
          gtfs_route_id?: string | null;
          id?: string;
          long_name?: string | null;
          organization_id?: string | null;
          short_name?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "fk_routes_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_routes_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_routes_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      sanction_escalation_log: {
        Row: {
          channel: string;
          delivery_status: string;
          id: string;
          notified_user_id: string | null;
          organization_id: string;
          organization_name: string | null;
          queue_entry_id: string;
          sent_at: string;
        };
        Insert: {
          channel: string;
          delivery_status?: string;
          id?: string;
          notified_user_id?: string | null;
          organization_id: string;
          organization_name?: string | null;
          queue_entry_id: string;
          sent_at?: string;
        };
        Update: {
          channel?: string;
          delivery_status?: string;
          id?: string;
          notified_user_id?: string | null;
          organization_id?: string;
          organization_name?: string | null;
          queue_entry_id?: string;
          sent_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "sanction_escalation_log_queue_entry_id_fkey";
            columns: ["queue_entry_id"];
            isOneToOne: false;
            referencedRelation: "sanction_review_queue";
            referencedColumns: ["id"];
          },
        ];
      };
      sanction_review_queue: {
        Row: {
          contract_id: string;
          created_at: string;
          id: string;
          ledger_entry_id: string;
          operator_name: string | null;
          organization_id: string;
          organization_name: string | null;
          rejection_reason: string | null;
          reviewed_at: string | null;
          reviewed_by: string | null;
          set_id: string;
          status: string;
          vehicle_plate: string | null;
          verdict_evidence: Json;
        };
        Insert: {
          contract_id: string;
          created_at?: string;
          id?: string;
          ledger_entry_id: string;
          operator_name?: string | null;
          organization_id: string;
          organization_name?: string | null;
          rejection_reason?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          set_id: string;
          status?: string;
          vehicle_plate?: string | null;
          verdict_evidence: Json;
        };
        Update: {
          contract_id?: string;
          created_at?: string;
          id?: string;
          ledger_entry_id?: string;
          operator_name?: string | null;
          organization_id?: string;
          organization_name?: string | null;
          rejection_reason?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          set_id?: string;
          status?: string;
          vehicle_plate?: string | null;
          verdict_evidence?: Json;
        };
        Relationships: [];
      };
      service_manifests: {
        Row: {
          contract_id: string;
          created_at: string;
          description: string | null;
          id: string;
          name: string;
          organization_id: string;
          penalties_payload: Json;
          sla_template_id: string | null;
          vertical: string | null;
        };
        Insert: {
          contract_id: string;
          created_at?: string;
          description?: string | null;
          id: string;
          name: string;
          organization_id: string;
          penalties_payload: Json;
          sla_template_id?: string | null;
          vertical?: string | null;
        };
        Update: {
          contract_id?: string;
          created_at?: string;
          description?: string | null;
          id?: string;
          name?: string;
          organization_id?: string;
          penalties_payload?: Json;
          sla_template_id?: string | null;
          vertical?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "service_manifests_contract_id_fkey";
            columns: ["contract_id"];
            isOneToOne: false;
            referencedRelation: "contracts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_manifests_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_manifests_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_manifests_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_manifests_sla_template_id_fkey";
            columns: ["sla_template_id"];
            isOneToOne: false;
            referencedRelation: "sla_templates";
            referencedColumns: ["id"];
          },
        ];
      };
      shadow_execution_transitions: {
        Row: {
          from_status: string;
          id: string;
          organization_id: string;
          reason: string | null;
          shadow_id: string;
          to_status: string;
          transitioned_at: string;
          transitioned_by: string | null;
        };
        Insert: {
          from_status: string;
          id?: string;
          organization_id: string;
          reason?: string | null;
          shadow_id: string;
          to_status: string;
          transitioned_at?: string;
          transitioned_by?: string | null;
        };
        Update: {
          from_status?: string;
          id?: string;
          organization_id?: string;
          reason?: string | null;
          shadow_id?: string;
          to_status?: string;
          transitioned_at?: string;
          transitioned_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "shadow_execution_transitions_shadow_id_fkey";
            columns: ["shadow_id"];
            isOneToOne: false;
            referencedRelation: "shadow_executions";
            referencedColumns: ["id"];
          },
        ];
      };
      shadow_executions: {
        Row: {
          avoided_penalty_cents: number | null;
          chat_id: number;
          counted_from_utc: string;
          created_at_utc: string;
          dismissed_at_utc: string | null;
          dismissed_by_user_id: string | null;
          dismissed_reason: string | null;
          id: string;
          message_ts: number;
          operator_id: string;
          organization_id: string;
          origin_channel: string;
          origin_evidence_id: string;
          reconciled_at_utc: string | null;
          reconciled_by_user_id: string | null;
          reconciled_execution_id: string | null;
          recovered_amount_cents: number | null;
          status: string;
          telegram_message_id: number;
        };
        Insert: {
          avoided_penalty_cents?: number | null;
          chat_id: number;
          counted_from_utc?: string;
          created_at_utc?: string;
          dismissed_at_utc?: string | null;
          dismissed_by_user_id?: string | null;
          dismissed_reason?: string | null;
          id?: string;
          message_ts: number;
          operator_id: string;
          organization_id: string;
          origin_channel?: string;
          origin_evidence_id: string;
          reconciled_at_utc?: string | null;
          reconciled_by_user_id?: string | null;
          reconciled_execution_id?: string | null;
          recovered_amount_cents?: number | null;
          status?: string;
          telegram_message_id: number;
        };
        Update: {
          avoided_penalty_cents?: number | null;
          chat_id?: number;
          counted_from_utc?: string;
          created_at_utc?: string;
          dismissed_at_utc?: string | null;
          dismissed_by_user_id?: string | null;
          dismissed_reason?: string | null;
          id?: string;
          message_ts?: number;
          operator_id?: string;
          organization_id?: string;
          origin_channel?: string;
          origin_evidence_id?: string;
          reconciled_at_utc?: string | null;
          reconciled_by_user_id?: string | null;
          reconciled_execution_id?: string | null;
          recovered_amount_cents?: number | null;
          status?: string;
          telegram_message_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: "shadow_executions_origin_evidence_id_fkey";
            columns: ["origin_evidence_id"];
            isOneToOne: true;
            referencedRelation: "telegram_evidence_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      shadow_mode_simulations: {
        Row: {
          actual_at_risk_revenue_cents: number;
          actual_compliance_rate: number;
          actual_lost_revenue_cents: number;
          actual_protected_revenue_cents: number;
          baseline_dispute_rate: number;
          created_at: string;
          evidence_quality_rate: number;
          generated_at_utc: string;
          generated_by_user_id: string;
          id: string;
          incident_count: number;
          manual_enforcement_cost_per_incident_cents: number;
          organization_id: string;
          period_end_utc: string;
          period_start_utc: string;
          revenue_protected_by_platform_cents: number;
          roi_percentage: number;
          simulated_lost_revenue_cents: number;
          simulation_name: string;
          simulation_parameters: Json;
        };
        Insert: {
          actual_at_risk_revenue_cents: number;
          actual_compliance_rate: number;
          actual_lost_revenue_cents: number;
          actual_protected_revenue_cents: number;
          baseline_dispute_rate: number;
          created_at?: string;
          evidence_quality_rate?: number;
          generated_at_utc?: string;
          generated_by_user_id: string;
          id?: string;
          incident_count: number;
          manual_enforcement_cost_per_incident_cents: number;
          organization_id: string;
          period_end_utc: string;
          period_start_utc: string;
          revenue_protected_by_platform_cents: number;
          roi_percentage: number;
          simulated_lost_revenue_cents: number;
          simulation_name: string;
          simulation_parameters?: Json;
        };
        Update: {
          actual_at_risk_revenue_cents?: number;
          actual_compliance_rate?: number;
          actual_lost_revenue_cents?: number;
          actual_protected_revenue_cents?: number;
          baseline_dispute_rate?: number;
          created_at?: string;
          evidence_quality_rate?: number;
          generated_at_utc?: string;
          generated_by_user_id?: string;
          id?: string;
          incident_count?: number;
          manual_enforcement_cost_per_incident_cents?: number;
          organization_id?: string;
          period_end_utc?: string;
          period_start_utc?: string;
          revenue_protected_by_platform_cents?: number;
          roi_percentage?: number;
          simulated_lost_revenue_cents?: number;
          simulation_name?: string;
          simulation_parameters?: Json;
        };
        Relationships: [];
      };
      shadow_verdicts: {
        Row: {
          contract_id: string;
          created_at: string;
          divergence_type: string;
          engine_verdict: string;
          engine_verdict_at_utc: string;
          engine_version: string;
          id: string;
          manual_reviewed_by: string | null;
          manual_verdict: string | null;
          manual_verdict_at_utc: string | null;
          organization_id: string;
          set_id: string;
          traceability_hash: string;
          verdict_evidence: Json;
        };
        Insert: {
          contract_id: string;
          created_at?: string;
          divergence_type?: string;
          engine_verdict: string;
          engine_verdict_at_utc: string;
          engine_version: string;
          id?: string;
          manual_reviewed_by?: string | null;
          manual_verdict?: string | null;
          manual_verdict_at_utc?: string | null;
          organization_id: string;
          set_id: string;
          traceability_hash: string;
          verdict_evidence: Json;
        };
        Update: {
          contract_id?: string;
          created_at?: string;
          divergence_type?: string;
          engine_verdict?: string;
          engine_verdict_at_utc?: string;
          engine_version?: string;
          id?: string;
          manual_reviewed_by?: string | null;
          manual_verdict?: string | null;
          manual_verdict_at_utc?: string | null;
          organization_id?: string;
          set_id?: string;
          traceability_hash?: string;
          verdict_evidence?: Json;
        };
        Relationships: [];
      };
      sla_audit_ledger: {
        Row: {
          actor_id: string | null;
          actor_type: string | null;
          contract_id: string;
          id: number;
          occurred_at_utc: string;
          payload: Json;
          payload_hmac: string | null;
          plan_version: number;
          set_id: string | null;
          type: string;
        };
        Insert: {
          actor_id?: string | null;
          actor_type?: string | null;
          contract_id: string;
          id?: never;
          occurred_at_utc: string;
          payload?: Json;
          payload_hmac?: string | null;
          plan_version: number;
          set_id?: string | null;
          type: string;
        };
        Update: {
          actor_id?: string | null;
          actor_type?: string | null;
          contract_id?: string;
          id?: never;
          occurred_at_utc?: string;
          payload?: Json;
          payload_hmac?: string | null;
          plan_version?: number;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [];
      };
      sla_audit_ledger_p0: {
        Row: {
          contract_id: string | null;
          id: string;
          new_value: string | null;
          occurred_at_utc: string;
          old_value: string | null;
          operator_id: string | null;
          organization_id: string;
          payload: Json | null;
          plan_version: number | null;
          reason: string | null;
          set_id: string | null;
          type: string;
        };
        Insert: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type: string;
        };
        Update: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc?: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id?: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [];
      };
      sla_audit_ledger_p1: {
        Row: {
          contract_id: string | null;
          id: string;
          new_value: string | null;
          occurred_at_utc: string;
          old_value: string | null;
          operator_id: string | null;
          organization_id: string;
          payload: Json | null;
          plan_version: number | null;
          reason: string | null;
          set_id: string | null;
          type: string;
        };
        Insert: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type: string;
        };
        Update: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc?: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id?: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [];
      };
      sla_audit_ledger_p2: {
        Row: {
          contract_id: string | null;
          id: string;
          new_value: string | null;
          occurred_at_utc: string;
          old_value: string | null;
          operator_id: string | null;
          organization_id: string;
          payload: Json | null;
          plan_version: number | null;
          reason: string | null;
          set_id: string | null;
          type: string;
        };
        Insert: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type: string;
        };
        Update: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc?: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id?: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [];
      };
      sla_audit_ledger_p3: {
        Row: {
          contract_id: string | null;
          id: string;
          new_value: string | null;
          occurred_at_utc: string;
          old_value: string | null;
          operator_id: string | null;
          organization_id: string;
          payload: Json | null;
          plan_version: number | null;
          reason: string | null;
          set_id: string | null;
          type: string;
        };
        Insert: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type: string;
        };
        Update: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc?: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id?: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [];
      };
      sla_audit_ledger_v2: {
        Row: {
          contract_id: string | null;
          id: string;
          new_value: string | null;
          occurred_at_utc: string;
          old_value: string | null;
          operator_id: string | null;
          organization_id: string;
          payload: Json | null;
          plan_version: number | null;
          reason: string | null;
          set_id: string | null;
          type: string;
        };
        Insert: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type: string;
        };
        Update: {
          contract_id?: string | null;
          id?: string;
          new_value?: string | null;
          occurred_at_utc?: string;
          old_value?: string | null;
          operator_id?: string | null;
          organization_id?: string;
          payload?: Json | null;
          plan_version?: number | null;
          reason?: string | null;
          set_id?: string | null;
          type?: string;
        };
        Relationships: [
          {
            foreignKeyName: "sla_audit_ledger_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sla_audit_ledger_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sla_audit_ledger_v2_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      sla_template_audit_log: {
        Row: {
          action: string;
          actor_session_id: string;
          id: string;
          occurred_at_utc: string;
          organization_id: string;
          template_id: string;
          template_snapshot: Json;
        };
        Insert: {
          action: string;
          actor_session_id: string;
          id?: string;
          occurred_at_utc?: string;
          organization_id: string;
          template_id: string;
          template_snapshot: Json;
        };
        Update: {
          action?: string;
          actor_session_id?: string;
          id?: string;
          occurred_at_utc?: string;
          organization_id?: string;
          template_id?: string;
          template_snapshot?: Json;
        };
        Relationships: [];
      };
      sla_templates: {
        Row: {
          created_at: string;
          description: string | null;
          id: string;
          name: string;
          organization_id: string;
          penalties_payload: Json;
          vertical: string | null;
        };
        Insert: {
          created_at?: string;
          description?: string | null;
          id?: string;
          name: string;
          organization_id: string;
          penalties_payload: Json;
          vertical?: string | null;
        };
        Update: {
          created_at?: string;
          description?: string | null;
          id?: string;
          name?: string;
          organization_id?: string;
          penalties_payload?: Json;
          vertical?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "sla_templates_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sla_templates_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sla_templates_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      spatial_ref_sys: {
        Row: {
          auth_name: string | null;
          auth_srid: number | null;
          proj4text: string | null;
          srid: number;
          srtext: string | null;
        };
        Insert: {
          auth_name?: string | null;
          auth_srid?: number | null;
          proj4text?: string | null;
          srid: number;
          srtext?: string | null;
        };
        Update: {
          auth_name?: string | null;
          auth_srid?: number | null;
          proj4text?: string | null;
          srid?: number;
          srtext?: string | null;
        };
        Relationships: [];
      };
      spoofing_audit_entries: {
        Row: {
          asset_id: string | null;
          content_hash: string;
          created_at: string;
          device_id: string;
          fact_ids: string[];
          facts_analyzed: number;
          id: string;
          organization_id: string;
          review_outcome: string | null;
          reviewed_at: string | null;
          reviewed_by: string | null;
          risk_score: number;
          signals: Json;
          window_end: string;
          window_start: string;
        };
        Insert: {
          asset_id?: string | null;
          content_hash: string;
          created_at?: string;
          device_id: string;
          fact_ids: string[];
          facts_analyzed: number;
          id?: string;
          organization_id: string;
          review_outcome?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          risk_score: number;
          signals?: Json;
          window_end: string;
          window_start: string;
        };
        Update: {
          asset_id?: string | null;
          content_hash?: string;
          created_at?: string;
          device_id?: string;
          fact_ids?: string[];
          facts_analyzed?: number;
          id?: string;
          organization_id?: string;
          review_outcome?: string | null;
          reviewed_at?: string | null;
          reviewed_by?: string | null;
          risk_score?: number;
          signals?: Json;
          window_end?: string;
          window_start?: string;
        };
        Relationships: [];
      };
      super_admin_access_log: {
        Row: {
          action: string;
          caller_user_id: string;
          id: string;
          ip_address: string | null;
          justification: string;
          occurred_at: string;
          request_params: Json | null;
          target_org_id: string | null;
          ticket_id: string;
        };
        Insert: {
          action: string;
          caller_user_id: string;
          id?: string;
          ip_address?: string | null;
          justification?: string;
          occurred_at?: string;
          request_params?: Json | null;
          target_org_id?: string | null;
          ticket_id: string;
        };
        Update: {
          action?: string;
          caller_user_id?: string;
          id?: string;
          ip_address?: string | null;
          justification?: string;
          occurred_at?: string;
          request_params?: Json | null;
          target_org_id?: string | null;
          ticket_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "super_admin_access_log_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "super_admin_access_log_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "super_admin_access_log_target_org_id_fkey";
            columns: ["target_org_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      super_admin_mfa_lockouts: {
        Row: {
          failed_attempts: number;
          last_attempt: string;
          locked_until: string | null;
          user_id: string;
        };
        Insert: {
          failed_attempts?: number;
          last_attempt?: string;
          locked_until?: string | null;
          user_id: string;
        };
        Update: {
          failed_attempts?: number;
          last_attempt?: string;
          locked_until?: string | null;
          user_id?: string;
        };
        Relationships: [];
      };
      super_admin_recovery_codes: {
        Row: {
          code_hash: string;
          created_at: string;
          id: string;
          used_at: string | null;
          user_id: string;
        };
        Insert: {
          code_hash: string;
          created_at?: string;
          id?: string;
          used_at?: string | null;
          user_id: string;
        };
        Update: {
          code_hash?: string;
          created_at?: string;
          id?: string;
          used_at?: string | null;
          user_id?: string;
        };
        Relationships: [];
      };
      super_admin_users: {
        Row: {
          created_at: string;
          email: string;
          id: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          email: string;
          id?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          email?: string;
          id?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      system_audit_log: {
        Row: {
          actor_type: string | null;
          event_type: string;
          id: string;
          impersonator_id: string | null;
          occurred_at: string;
          organization_id: string | null;
          organization_name: string | null;
          payload: Json | null;
          reason: string | null;
          severity: string;
          source: string | null;
        };
        Insert: {
          actor_type?: string | null;
          event_type: string;
          id?: string;
          impersonator_id?: string | null;
          occurred_at?: string;
          organization_id?: string | null;
          organization_name?: string | null;
          payload?: Json | null;
          reason?: string | null;
          severity?: string;
          source?: string | null;
        };
        Update: {
          actor_type?: string | null;
          event_type?: string;
          id?: string;
          impersonator_id?: string | null;
          occurred_at?: string;
          organization_id?: string | null;
          organization_name?: string | null;
          payload?: Json | null;
          reason?: string | null;
          severity?: string;
          source?: string | null;
        };
        Relationships: [];
      };
      telegram_binding_tokens: {
        Row: {
          code: string;
          created_at_utc: string;
          created_by_user_id: string;
          driver_id: string;
          expires_at_utc: string;
          id: string;
          organization_id: string;
          used_at_utc: string | null;
        };
        Insert: {
          code: string;
          created_at_utc?: string;
          created_by_user_id: string;
          driver_id: string;
          expires_at_utc: string;
          id?: string;
          organization_id: string;
          used_at_utc?: string | null;
        };
        Update: {
          code?: string;
          created_at_utc?: string;
          created_by_user_id?: string;
          driver_id?: string;
          expires_at_utc?: string;
          id?: string;
          organization_id?: string;
          used_at_utc?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_binding_tokens_driver_id_fkey";
            columns: ["driver_id"];
            isOneToOne: false;
            referencedRelation: "drivers";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_chat_bindings: {
        Row: {
          binding_token_id: string;
          bound_at_utc: string;
          chat_id: number;
          driver_id: string;
          id: string;
          organization_id: string;
          unbound_at_utc: string | null;
        };
        Insert: {
          binding_token_id: string;
          bound_at_utc?: string;
          chat_id: number;
          driver_id: string;
          id?: string;
          organization_id: string;
          unbound_at_utc?: string | null;
        };
        Update: {
          binding_token_id?: string;
          bound_at_utc?: string;
          chat_id?: number;
          driver_id?: string;
          id?: string;
          organization_id?: string;
          unbound_at_utc?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_chat_bindings_binding_token_id_fkey";
            columns: ["binding_token_id"];
            isOneToOne: false;
            referencedRelation: "telegram_binding_tokens";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "telegram_chat_bindings_driver_id_fkey";
            columns: ["driver_id"];
            isOneToOne: false;
            referencedRelation: "drivers";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_evidence_categories: {
        Row: {
          category: string;
          evidence_upload_id: string;
          id: string;
          organization_id: string;
          tagged_at_utc: string;
        };
        Insert: {
          category: string;
          evidence_upload_id: string;
          id?: string;
          organization_id: string;
          tagged_at_utc?: string;
        };
        Update: {
          category?: string;
          evidence_upload_id?: string;
          id?: string;
          organization_id?: string;
          tagged_at_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_evidence_categories_evidence_upload_id_fkey";
            columns: ["evidence_upload_id"];
            isOneToOne: true;
            referencedRelation: "telegram_evidence_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_evidence_links: {
        Row: {
          evidence_upload_id: string;
          execution_set_id: string;
          id: string;
          linked_at_utc: string;
          linked_by_user_id: string | null;
          organization_id: string;
          source: string;
        };
        Insert: {
          evidence_upload_id: string;
          execution_set_id: string;
          id?: string;
          linked_at_utc?: string;
          linked_by_user_id?: string | null;
          organization_id: string;
          source?: string;
        };
        Update: {
          evidence_upload_id?: string;
          execution_set_id?: string;
          id?: string;
          linked_at_utc?: string;
          linked_by_user_id?: string | null;
          organization_id?: string;
          source?: string;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_evidence_links_evidence_upload_id_fkey";
            columns: ["evidence_upload_id"];
            isOneToOne: false;
            referencedRelation: "telegram_evidence_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_evidence_metadata: {
        Row: {
          evidence_upload_id: string;
          exif_data: Json;
          extracted_at_utc: string;
          id: string;
          organization_id: string;
        };
        Insert: {
          evidence_upload_id: string;
          exif_data?: Json;
          extracted_at_utc?: string;
          id?: string;
          organization_id: string;
        };
        Update: {
          evidence_upload_id?: string;
          exif_data?: Json;
          extracted_at_utc?: string;
          id?: string;
          organization_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_evidence_metadata_evidence_upload_id_fkey";
            columns: ["evidence_upload_id"];
            isOneToOne: false;
            referencedRelation: "telegram_evidence_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_evidence_uploads: {
        Row: {
          chat_id: number;
          clock_drift_seconds: number | null;
          driver_id: string;
          file_name: string;
          forensic_hash: string;
          id: string;
          linked_set_id: string | null;
          mime_type: string | null;
          organization_id: string;
          payload_hmac: string | null;
          requires_manual_link: boolean;
          source: string;
          storage_path: string;
          suggested_category: string | null;
          suggestion_expires_at_utc: string | null;
          suggestion_sealed_at_utc: string | null;
          telegram_message_date: string;
          telegram_message_id: number;
          uploaded_at_utc: string;
        };
        Insert: {
          chat_id: number;
          clock_drift_seconds?: number | null;
          driver_id: string;
          file_name: string;
          forensic_hash: string;
          id?: string;
          linked_set_id?: string | null;
          mime_type?: string | null;
          organization_id: string;
          payload_hmac?: string | null;
          requires_manual_link?: boolean;
          source?: string;
          storage_path: string;
          suggested_category?: string | null;
          suggestion_expires_at_utc?: string | null;
          suggestion_sealed_at_utc?: string | null;
          telegram_message_date: string;
          telegram_message_id: number;
          uploaded_at_utc?: string;
        };
        Update: {
          chat_id?: number;
          clock_drift_seconds?: number | null;
          driver_id?: string;
          file_name?: string;
          forensic_hash?: string;
          id?: string;
          linked_set_id?: string | null;
          mime_type?: string | null;
          organization_id?: string;
          payload_hmac?: string | null;
          requires_manual_link?: boolean;
          source?: string;
          storage_path?: string;
          suggested_category?: string | null;
          suggestion_expires_at_utc?: string | null;
          suggestion_sealed_at_utc?: string | null;
          telegram_message_date?: string;
          telegram_message_id?: number;
          uploaded_at_utc?: string;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_evidence_uploads_driver_id_fkey";
            columns: ["driver_id"];
            isOneToOne: false;
            referencedRelation: "drivers";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_pending_links: {
        Row: {
          created_at_utc: string;
          driver_id: string;
          evidence_upload_id: string;
          execution_set_id: string;
          expires_at_utc: string;
          id: string;
          is_resolved: boolean;
          organization_id: string;
          short_id: string;
        };
        Insert: {
          created_at_utc?: string;
          driver_id: string;
          evidence_upload_id: string;
          execution_set_id: string;
          expires_at_utc: string;
          id?: string;
          is_resolved?: boolean;
          organization_id: string;
          short_id: string;
        };
        Update: {
          created_at_utc?: string;
          driver_id?: string;
          evidence_upload_id?: string;
          execution_set_id?: string;
          expires_at_utc?: string;
          id?: string;
          is_resolved?: boolean;
          organization_id?: string;
          short_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "telegram_pending_links_evidence_upload_id_fkey";
            columns: ["evidence_upload_id"];
            isOneToOne: false;
            referencedRelation: "telegram_evidence_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      telegram_status_queries: {
        Row: {
          chat_id: number;
          compliance_snapshot: Json;
          driver_id: string;
          id: string;
          organization_id: string;
          queried_at_utc: string;
          set_id: string | null;
        };
        Insert: {
          chat_id: number;
          compliance_snapshot: Json;
          driver_id: string;
          id?: string;
          organization_id: string;
          queried_at_utc?: string;
          set_id?: string | null;
        };
        Update: {
          chat_id?: number;
          compliance_snapshot?: Json;
          driver_id?: string;
          id?: string;
          organization_id?: string;
          queried_at_utc?: string;
          set_id?: string | null;
        };
        Relationships: [];
      };
      telegram_user_consents: {
        Row: {
          accepted_at_utc: string;
          chat_id: number;
          consent_version: string;
          created_at_utc: string;
          id: string;
          ip_hash: string | null;
        };
        Insert: {
          accepted_at_utc?: string;
          chat_id: number;
          consent_version?: string;
          created_at_utc?: string;
          id?: string;
          ip_hash?: string | null;
        };
        Update: {
          accepted_at_utc?: string;
          chat_id?: number;
          consent_version?: string;
          created_at_utc?: string;
          id?: string;
          ip_hash?: string | null;
        };
        Relationships: [];
      };
      tenant_billing_events: {
        Row: {
          changed_by_super_admin_id: string | null;
          event_type: string;
          id: string;
          new_max_contracts: number | null;
          new_max_vehicles: number | null;
          new_plan: string | null;
          occurred_at_utc: string;
          old_max_contracts: number | null;
          old_max_vehicles: number | null;
          old_plan: string | null;
          organization_id: string | null;
          organization_name: string | null;
          reason: string | null;
        };
        Insert: {
          changed_by_super_admin_id?: string | null;
          event_type: string;
          id?: string;
          new_max_contracts?: number | null;
          new_max_vehicles?: number | null;
          new_plan?: string | null;
          occurred_at_utc?: string;
          old_max_contracts?: number | null;
          old_max_vehicles?: number | null;
          old_plan?: string | null;
          organization_id?: string | null;
          organization_name?: string | null;
          reason?: string | null;
        };
        Update: {
          changed_by_super_admin_id?: string | null;
          event_type?: string;
          id?: string;
          new_max_contracts?: number | null;
          new_max_vehicles?: number | null;
          new_plan?: string | null;
          occurred_at_utc?: string;
          old_max_contracts?: number | null;
          old_max_vehicles?: number | null;
          old_plan?: string | null;
          organization_id?: string | null;
          organization_name?: string | null;
          reason?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "tenant_billing_events_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tenant_billing_events_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tenant_billing_events_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      trips_audit: {
        Row: {
          created_at: string | null;
          driver_id: string | null;
          end_time: string | null;
          id: string;
          organization_id: string | null;
          route_id: string | null;
          source_type: string | null;
          start_time: string | null;
          status: string | null;
        };
        Insert: {
          created_at?: string | null;
          driver_id?: string | null;
          end_time?: string | null;
          id?: string;
          organization_id?: string | null;
          route_id?: string | null;
          source_type?: string | null;
          start_time?: string | null;
          status?: string | null;
        };
        Update: {
          created_at?: string | null;
          driver_id?: string | null;
          end_time?: string | null;
          id?: string;
          organization_id?: string | null;
          route_id?: string | null;
          source_type?: string | null;
          start_time?: string | null;
          status?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "fk_trips_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_trips_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_trips_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "trips_audit_driver_id_fkey";
            columns: ["driver_id"];
            isOneToOne: false;
            referencedRelation: "drivers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "trips_audit_route_id_fkey";
            columns: ["route_id"];
            isOneToOne: false;
            referencedRelation: "routes";
            referencedColumns: ["id"];
          },
        ];
      };
      user_roles: {
        Row: {
          contractor_id: string | null;
          created_at: string;
          is_active: boolean;
          organization_id: string;
          organization_name: string | null;
          role: string;
          user_email: string | null;
          user_id: string;
        };
        Insert: {
          contractor_id?: string | null;
          created_at?: string;
          is_active?: boolean;
          organization_id: string;
          organization_name?: string | null;
          role: string;
          user_email?: string | null;
          user_id: string;
        };
        Update: {
          contractor_id?: string | null;
          created_at?: string;
          is_active?: boolean;
          organization_id?: string;
          organization_name?: string | null;
          role?: string;
          user_email?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_roles_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_roles_contractor_id_fkey";
            columns: ["contractor_id"];
            isOneToOne: false;
            referencedRelation: "contractors_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      vehicles: {
        Row: {
          capacity: number;
          created_at: string;
          device_serial: string | null;
          external_id: string | null;
          id: string;
          model: string | null;
          organization_id: string;
          plate: string;
          status: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          capacity?: number;
          created_at?: string;
          device_serial?: string | null;
          external_id?: string | null;
          id?: string;
          model?: string | null;
          organization_id: string;
          plate: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          capacity?: number;
          created_at?: string;
          device_serial?: string | null;
          external_id?: string | null;
          id?: string;
          model?: string | null;
          organization_id?: string;
          plate?: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "fk_vehicles_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_vehicles_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "fk_vehicles_organization";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      contractors_view: {
        Row: {
          contact_name: string | null;
          created_at_utc: string | null;
          id: string | null;
          name: string | null;
          organization_id: string | null;
          primary_email: string | null;
          tax_id: string | null;
        };
        Insert: {
          contact_name?: string | null;
          created_at_utc?: string | null;
          id?: string | null;
          name?: string | null;
          organization_id?: string | null;
          primary_email?: never;
          tax_id?: never;
        };
        Update: {
          contact_name?: string | null;
          created_at_utc?: string | null;
          id?: string | null;
          name?: string | null;
          organization_id?: string | null;
          primary_email?: never;
          tax_id?: never;
        };
        Relationships: [
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "contractors_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      geography_columns: {
        Row: {
          coord_dimension: number | null;
          f_geography_column: unknown;
          f_table_catalog: unknown;
          f_table_name: unknown;
          f_table_schema: unknown;
          srid: number | null;
          type: string | null;
        };
        Relationships: [];
      };
      geometry_columns: {
        Row: {
          coord_dimension: number | null;
          f_geometry_column: unknown;
          f_table_catalog: string | null;
          f_table_name: unknown;
          f_table_schema: unknown;
          srid: number | null;
          type: string | null;
        };
        Insert: {
          coord_dimension?: number | null;
          f_geometry_column?: unknown;
          f_table_catalog?: string | null;
          f_table_name?: unknown;
          f_table_schema?: unknown;
          srid?: number | null;
          type?: string | null;
        };
        Update: {
          coord_dimension?: number | null;
          f_geometry_column?: unknown;
          f_table_catalog?: string | null;
          f_table_name?: unknown;
          f_table_schema?: unknown;
          srid?: number | null;
          type?: string | null;
        };
        Relationships: [];
      };
      invitations_view: {
        Row: {
          accepted_at_utc: string | null;
          created_at_utc: string | null;
          email: string | null;
          expires_at_utc: string | null;
          id: string | null;
          invited_by_user_id: string | null;
          organization_id: string | null;
          role: string | null;
          status: string | null;
        };
        Insert: {
          accepted_at_utc?: string | null;
          created_at_utc?: string | null;
          email?: never;
          expires_at_utc?: string | null;
          id?: string | null;
          invited_by_user_id?: string | null;
          organization_id?: string | null;
          role?: string | null;
          status?: never;
        };
        Update: {
          accepted_at_utc?: string | null;
          created_at_utc?: string | null;
          email?: never;
          expires_at_utc?: string | null;
          id?: string | null;
          invited_by_user_id?: string | null;
          organization_id?: string | null;
          role?: string | null;
          status?: never;
        };
        Relationships: [
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_health_view";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "invitations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "super_admin_tenant_technical_health_view";
            referencedColumns: ["id"];
          },
        ];
      };
      mv_evidence_volume: {
        Row: {
          organization_id: string | null;
          total_historical: number | null;
          total_monthly: number | null;
        };
        Relationships: [];
      };
      super_admin_tenant_health_view: {
        Row: {
          active_contract_count: number | null;
          billing_day: number | null;
          capabilities: Json | null;
          cnpj: string | null;
          contact_email: string | null;
          created_at: string | null;
          dwell_time_seconds: number | null;
          external_id: string | null;
          id: string | null;
          is_active: boolean | null;
          last_telemetry_at: string | null;
          legal_name: string | null;
          max_active_contracts: number | null;
          max_vehicles: number | null;
          name: string | null;
          open_critical_alert_count: number | null;
          organization_type: string | null;
          plan_type: string | null;
          status: string | null;
          tool_cost_cents: number | null;
          updated_at: string | null;
        };
        Relationships: [];
      };
      super_admin_tenant_technical_health_view: {
        Row: {
          id: string | null;
          last_check_at: string | null;
          replication_status: string | null;
          schema_integrity_status: string | null;
          schema_version: string | null;
        };
        Relationships: [];
      };
      v_roi_summary: {
        Row: {
          organization_id: string | null;
          pending_orphans: number | null;
          recovered_trips: number | null;
          roi_bps: number | null;
          tool_cost_cents: number | null;
          total_avoided_penalty_cents: number | null;
          total_linked_trips: number | null;
          total_recovered_cents: number | null;
        };
        Relationships: [];
      };
      vw_device_heartbeat_status: {
        Row: {
          asset_id: string | null;
          fleet_active_ratio: number | null;
          gap_seconds: number | null;
          last_seen_utc: string | null;
          organization_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "canonical_facts_asset_id_fkey";
            columns: ["asset_id"];
            isOneToOne: false;
            referencedRelation: "vehicles";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Functions: {
      _postgis_deprecate: {
        Args: { newname: string; oldname: string; version: string };
        Returns: undefined;
      };
      _postgis_index_extent: {
        Args: { col: string; tbl: unknown };
        Returns: unknown;
      };
      _postgis_pgsql_version: { Args: never; Returns: string };
      _postgis_scripts_pgsql_version: { Args: never; Returns: string };
      _postgis_selectivity: {
        Args: { att_name: string; geom: unknown; mode?: string; tbl: unknown };
        Returns: number;
      };
      _postgis_stats: {
        Args: { ""?: string; att_name: string; tbl: unknown };
        Returns: string;
      };
      _st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_contains: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      _st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      _st_crosses: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_dwithin: {
        Args: {
          geog1: unknown;
          geog2: unknown;
          tolerance: number;
          use_spheroid?: boolean;
        };
        Returns: boolean;
      };
      _st_equals: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_intersects: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown };
        Returns: number;
      };
      _st_longestline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      _st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      _st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_overlaps: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_sortablehash: { Args: { geom: unknown }; Returns: number };
      _st_touches: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      _st_voronoi: {
        Args: {
          clip?: unknown;
          g1: unknown;
          return_polygons?: boolean;
          tolerance?: number;
        };
        Returns: unknown;
      };
      _st_within: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      accept_contract_by_contractor: {
        Args: { p_token: string };
        Returns: Json;
      };
      accept_invitation: {
        Args: { p_token: string; p_user_id: string };
        Returns: undefined;
      };
      addauth: { Args: { "": string }; Returns: boolean };
      addgeometrycolumn:
        | {
            Args: {
              catalog_name: string;
              column_name: string;
              new_dim: number;
              new_srid_in: number;
              new_type: string;
              schema_name: string;
              table_name: string;
              use_typmod?: boolean;
            };
            Returns: string;
          }
        | {
            Args: {
              column_name: string;
              new_dim: number;
              new_srid: number;
              new_type: string;
              schema_name: string;
              table_name: string;
              use_typmod?: boolean;
            };
            Returns: string;
          }
        | {
            Args: {
              column_name: string;
              new_dim: number;
              new_srid: number;
              new_type: string;
              table_name: string;
              use_typmod?: boolean;
            };
            Returns: string;
          };
      batch_update_contracts: { Args: { p_updates: Json }; Returns: Json };
      batch_update_vehicles: { Args: { p_updates: Json }; Returns: Json };
      batch_upsert_contractors: {
        Args: { p_org_id: string; p_rows: Json };
        Returns: number;
      };
      batch_upsert_contracts: {
        Args: { p_org_id: string; p_rows: Json };
        Returns: number;
      };
      batch_upsert_drivers: {
        Args: { p_org_id: string; p_rows: Json };
        Returns: number;
      };
      batch_upsert_operational_zones: {
        Args: { p_org_id: string; p_rows: Json };
        Returns: number;
      };
      batch_upsert_vehicles: {
        Args: { p_org_id: string; p_rows: Json };
        Returns: number;
      };
      check_and_close_execution_autonomously: {
        Args: {
          p_current_lat?: number;
          p_current_lng?: number;
          p_device_ts?: string;
          p_org_id: string;
          p_set_id: string;
        };
        Returns: Json;
      };
      check_execution_compliance: {
        Args: { p_org_id: string; p_set_id: string };
        Returns: boolean;
      };
      check_forensic_throttle: {
        Args: { p_org_id: string };
        Returns: {
          allowed: boolean;
          wait_seconds: number;
        }[];
      };
      check_mfa_lockout: { Args: { p_user_id: string }; Returns: Json };
      check_rls_enabled: { Args: { p_table_name: string }; Returns: boolean };
      check_schema_integrity: { Args: { p_org_id: string }; Returns: Json };
      check_telegram_rate_limit: {
        Args: { p_chat_id: number };
        Returns: boolean;
      };
      cleanup_expired_idempotency: {
        Args: { days_threshold?: number };
        Returns: number;
      };
      complete_execution: {
        Args: { p_org_id: string; p_reason?: string; p_set_id: string };
        Returns: boolean;
      };
      complete_idempotency_key: {
        Args: {
          p_id: string;
          p_response_body: Json;
          p_response_code: number;
          p_user_id: string;
        };
        Returns: undefined;
      };
      consume_telegram_binding_token: {
        Args: { p_chat_id: number; p_code: string };
        Returns: {
          driver_id: string;
          organization_id: string;
        }[];
      };
      create_execution_for_operator: {
        Args: {
          p_contract_id: string;
          p_destination_zone_id: string;
          p_driver_id: string;
          p_organization_id: string;
          p_origin_zone_id: string;
          p_vehicle_id: string;
          p_window_end_utc: string;
          p_window_start_utc: string;
        };
        Returns: string;
      };
      create_shadow_execution: {
        Args: {
          p_chat_id: number;
          p_evidence_id: string;
          p_message_ts: number;
          p_operator_id: string;
          p_org_id: string;
          p_telegram_message_id: number;
        };
        Returns: string;
      };
      custom_access_token_hook: { Args: { event: Json }; Returns: Json };
      deactivate_member: {
        Args: { p_target_user_id: string };
        Returns: undefined;
      };
      disablelongtransactions: { Args: never; Returns: string };
      dropgeometrycolumn:
        | {
            Args: {
              catalog_name: string;
              column_name: string;
              schema_name: string;
              table_name: string;
            };
            Returns: string;
          }
        | {
            Args: {
              column_name: string;
              schema_name: string;
              table_name: string;
            };
            Returns: string;
          }
        | {
            Args: { column_name: string; table_name: string };
            Returns: string;
          };
      dropgeometrytable:
        | {
            Args: {
              catalog_name: string;
              schema_name: string;
              table_name: string;
            };
            Returns: string;
          }
        | { Args: { schema_name: string; table_name: string }; Returns: string }
        | { Args: { table_name: string }; Returns: string };
      enablelongtransactions: { Args: never; Returns: string };
      equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      fail_idempotency_key: {
        Args: {
          p_id: string;
          p_response_body?: Json;
          p_response_code: number;
          p_user_id: string;
        };
        Returns: undefined;
      };
      find_execution_for_telegram: {
        Args: { p_driver_id: string; p_message_ts: number; p_org_id: string };
        Returns: string;
      };
      find_pending_trips_for_driver: {
        Args: { p_driver_id: string; p_limit?: number; p_org_id: string };
        Returns: {
          set_id: string;
          window_start_utc: string;
        }[];
      };
      generate_monthly_audit_package: {
        Args: {
          p_contract_id?: string;
          p_month: number;
          p_organization_id: string;
          p_year: number;
        };
        Returns: string;
      };
      geometry: { Args: { "": string }; Returns: unknown };
      geometry_above: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_below: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_cmp: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      geometry_contained_3d: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_contains: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_contains_3d: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_distance_box: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      geometry_distance_centroid: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      geometry_eq: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_ge: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_gt: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_le: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_left: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_lt: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overabove: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overbelow: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overlaps: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overlaps_3d: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overleft: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_overright: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_right: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_same: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_same_3d: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geometry_within: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      geomfromewkt: { Args: { "": string }; Returns: unknown };
      get_auth_role: { Args: never; Returns: string };
      get_batch_compliance_status: {
        Args: { p_org_id: string; p_set_ids: string[] };
        Returns: Json;
      };
      get_contract_for_review: { Args: { p_token: string }; Returns: Json };
      get_current_asset_status: {
        Args: { p_asset_id: string; p_organization_id: string };
        Returns: string;
      };
      get_device_heartbeat_status: {
        Args: { p_organization_id: string };
        Returns: {
          asset_id: string;
          fleet_active_ratio: number;
          gap_seconds: number;
          last_seen_utc: string;
        }[];
      };
      get_driver_status_query_count: {
        Args: { p_driver_id: string; p_org_id: string; p_set_id: string };
        Returns: Json;
      };
      get_missed_facts: {
        Args: { p_after_utc: string; p_limit?: number; p_org_id: string };
        Returns: {
          device_id: string;
          gps_timestamp: string;
          id: string;
          received_at: string;
        }[];
      };
      get_org_members: {
        Args: never;
        Returns: {
          email: string;
          invited_at: string;
          is_active: boolean;
          last_sign_in: string;
          role: string;
          user_id: string;
        }[];
      };
      get_pending_sanctions_count: {
        Args: { p_org_id: string };
        Returns: number;
      };
      get_rule_version_history: {
        Args: { p_contract_id: string };
        Returns: Json;
      };
      get_trip_compliance_status: {
        Args: { p_driver_id: string; p_org_id: string };
        Returns: Json;
      };
      gettransactionid: { Args: never; Returns: unknown };
      invite_user: {
        Args: {
          p_email: string;
          p_expires_at: string;
          p_invitation_id: string;
          p_role: string;
          p_token: string;
        };
        Returns: undefined;
      };
      jsonb_canonical_text: { Args: { p_input: Json }; Returns: string };
      longtransactionsenabled: { Args: never; Returns: boolean };
      mark_alert_viewed: {
        Args: { p_alert_id: string; p_user_id: string };
        Returns: undefined;
      };
      mask_cnpj: { Args: { raw_cnpj: string }; Returns: string };
      mask_email: { Args: { raw_email: string }; Returns: string };
      notify_pgrst_reload: { Args: never; Returns: undefined };
      offboard_driver: {
        Args: { p_driver_id: string; p_org_id: string };
        Returns: undefined;
      };
      populate_geometry_columns:
        | { Args: { tbl_oid: unknown; use_typmod?: boolean }; Returns: number }
        | { Args: { use_typmod?: boolean }; Returns: string };
      postgis_constraint_dims: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string };
        Returns: number;
      };
      postgis_constraint_srid: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string };
        Returns: number;
      };
      postgis_constraint_type: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string };
        Returns: string;
      };
      postgis_extensions_upgrade: { Args: never; Returns: string };
      postgis_full_version: { Args: never; Returns: string };
      postgis_geos_version: { Args: never; Returns: string };
      postgis_lib_build_date: { Args: never; Returns: string };
      postgis_lib_revision: { Args: never; Returns: string };
      postgis_lib_version: { Args: never; Returns: string };
      postgis_libjson_version: { Args: never; Returns: string };
      postgis_liblwgeom_version: { Args: never; Returns: string };
      postgis_libprotobuf_version: { Args: never; Returns: string };
      postgis_libxml_version: { Args: never; Returns: string };
      postgis_proj_version: { Args: never; Returns: string };
      postgis_scripts_build_date: { Args: never; Returns: string };
      postgis_scripts_installed: { Args: never; Returns: string };
      postgis_scripts_released: { Args: never; Returns: string };
      postgis_svn_version: { Args: never; Returns: string };
      postgis_type_name: {
        Args: {
          coord_dimension: number;
          geomname: string;
          use_new_name?: boolean;
        };
        Returns: string;
      };
      postgis_version: { Args: never; Returns: string };
      postgis_wagyu_version: { Args: never; Returns: string };
      process_gps_for_execution_transitions: {
        Args: {
          p_device_serial: string;
          p_device_ts?: string;
          p_lat: number;
          p_lng: number;
          p_org_id: string;
        };
        Returns: Json;
      };
      reactivate_member: {
        Args: { p_target_user_id: string };
        Returns: undefined;
      };
      record_forensic_failure: {
        Args: { p_org_id: string };
        Returns: undefined;
      };
      record_mfa_failure: { Args: { p_user_id: string }; Returns: Json };
      remove_member: { Args: { p_target_user_id: string }; Returns: undefined };
      reset_forensic_throttle: {
        Args: { p_org_id: string };
        Returns: undefined;
      };
      reset_mfa_lockout: { Args: { p_user_id: string }; Returns: undefined };
      resolve_telegram_orphan_with_link: {
        Args: { p_driver_id: string; p_short_id: string };
        Returns: string;
      };
      revoke_invitation: {
        Args: { p_invitation_id: string };
        Returns: undefined;
      };
      seal_forensic_evidence: {
        Args: {
          p_contract_id: string;
          p_idempotency_key: string;
          p_occurred_at_utc: string;
          p_organization_id: string;
          p_plan_version: number;
          p_sealed_by: string;
          p_set_id: string;
          p_verdict_type: string;
        };
        Returns: Json;
      };
      st_3dclosestpoint: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_3ddistance: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_3dlongestline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_3dmakebox: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_3dmaxdistance: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_3dshortestline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_addpoint: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_angle:
        | { Args: { line1: unknown; line2: unknown }; Returns: number }
        | {
            Args: { pt1: unknown; pt2: unknown; pt3: unknown; pt4?: unknown };
            Returns: number;
          };
      st_area:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number };
      st_asencodedpolyline: {
        Args: { geom: unknown; nprecision?: number };
        Returns: string;
      };
      st_asewkt: { Args: { "": string }; Returns: string };
      st_asgeojson:
        | {
            Args: {
              geog: unknown;
              maxdecimaldigits?: number;
              options?: number;
            };
            Returns: string;
          }
        | {
            Args: {
              geom: unknown;
              maxdecimaldigits?: number;
              options?: number;
            };
            Returns: string;
          }
        | {
            Args: {
              geom_column?: string;
              maxdecimaldigits?: number;
              pretty_bool?: boolean;
              r: Record<string, unknown>;
            };
            Returns: string;
          }
        | { Args: { "": string }; Returns: string };
      st_asgml:
        | {
            Args: {
              geog: unknown;
              id?: string;
              maxdecimaldigits?: number;
              nprefix?: string;
              options?: number;
            };
            Returns: string;
          }
        | {
            Args: {
              geom: unknown;
              maxdecimaldigits?: number;
              options?: number;
            };
            Returns: string;
          }
        | { Args: { "": string }; Returns: string }
        | {
            Args: {
              geog: unknown;
              id?: string;
              maxdecimaldigits?: number;
              nprefix?: string;
              options?: number;
              version: number;
            };
            Returns: string;
          }
        | {
            Args: {
              geom: unknown;
              id?: string;
              maxdecimaldigits?: number;
              nprefix?: string;
              options?: number;
              version: number;
            };
            Returns: string;
          };
      st_askml:
        | {
            Args: {
              geog: unknown;
              maxdecimaldigits?: number;
              nprefix?: string;
            };
            Returns: string;
          }
        | {
            Args: {
              geom: unknown;
              maxdecimaldigits?: number;
              nprefix?: string;
            };
            Returns: string;
          }
        | { Args: { "": string }; Returns: string };
      st_aslatlontext: {
        Args: { geom: unknown; tmpl?: string };
        Returns: string;
      };
      st_asmarc21: {
        Args: { format?: string; geom: unknown };
        Returns: string;
      };
      st_asmvtgeom: {
        Args: {
          bounds: unknown;
          buffer?: number;
          clip_geom?: boolean;
          extent?: number;
          geom: unknown;
        };
        Returns: unknown;
      };
      st_assvg:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; rel?: number };
            Returns: string;
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; rel?: number };
            Returns: string;
          }
        | { Args: { "": string }; Returns: string };
      st_astext: { Args: { "": string }; Returns: string };
      st_astwkb:
        | {
            Args: {
              geom: unknown;
              prec?: number;
              prec_m?: number;
              prec_z?: number;
              with_boxes?: boolean;
              with_sizes?: boolean;
            };
            Returns: string;
          }
        | {
            Args: {
              geom: unknown[];
              ids: number[];
              prec?: number;
              prec_m?: number;
              prec_z?: number;
              with_boxes?: boolean;
              with_sizes?: boolean;
            };
            Returns: string;
          };
      st_asx3d: {
        Args: { geom: unknown; maxdecimaldigits?: number; options?: number };
        Returns: string;
      };
      st_azimuth:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: number }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number };
      st_boundingdiagonal: {
        Args: { fits?: boolean; geom: unknown };
        Returns: unknown;
      };
      st_buffer:
        | {
            Args: { geom: unknown; options?: string; radius: number };
            Returns: unknown;
          }
        | {
            Args: { geom: unknown; quadsegs: number; radius: number };
            Returns: unknown;
          };
      st_centroid: { Args: { "": string }; Returns: unknown };
      st_clipbybox2d: {
        Args: { box: unknown; geom: unknown };
        Returns: unknown;
      };
      st_closestpoint: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_collect: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_concavehull: {
        Args: {
          param_allow_holes?: boolean;
          param_geom: unknown;
          param_pctconvex: number;
        };
        Returns: unknown;
      };
      st_contains: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_coorddim: { Args: { geometry: unknown }; Returns: number };
      st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      st_crosses: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_curvetoline: {
        Args: { flags?: number; geom: unknown; tol?: number; toltype?: number };
        Returns: unknown;
      };
      st_delaunaytriangles: {
        Args: { flags?: number; g1: unknown; tolerance?: number };
        Returns: unknown;
      };
      st_difference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number };
        Returns: unknown;
      };
      st_disjoint: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_distance:
        | {
            Args: { geog1: unknown; geog2: unknown; use_spheroid?: boolean };
            Returns: number;
          }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number };
      st_distancesphere:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
        | {
            Args: { geom1: unknown; geom2: unknown; radius: number };
            Returns: number;
          };
      st_distancespheroid: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_dwithin: {
        Args: {
          geog1: unknown;
          geog2: unknown;
          tolerance: number;
          use_spheroid?: boolean;
        };
        Returns: boolean;
      };
      st_equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      st_expand:
        | { Args: { box: unknown; dx: number; dy: number }; Returns: unknown }
        | {
            Args: { box: unknown; dx: number; dy: number; dz?: number };
            Returns: unknown;
          }
        | {
            Args: {
              dm?: number;
              dx: number;
              dy: number;
              dz?: number;
              geom: unknown;
            };
            Returns: unknown;
          };
      st_force3d: {
        Args: { geom: unknown; zvalue?: number };
        Returns: unknown;
      };
      st_force3dm: {
        Args: { geom: unknown; mvalue?: number };
        Returns: unknown;
      };
      st_force3dz: {
        Args: { geom: unknown; zvalue?: number };
        Returns: unknown;
      };
      st_force4d: {
        Args: { geom: unknown; mvalue?: number; zvalue?: number };
        Returns: unknown;
      };
      st_generatepoints:
        | { Args: { area: unknown; npoints: number }; Returns: unknown }
        | {
            Args: { area: unknown; npoints: number; seed: number };
            Returns: unknown;
          };
      st_geogfromtext: { Args: { "": string }; Returns: unknown };
      st_geographyfromtext: { Args: { "": string }; Returns: unknown };
      st_geohash:
        | { Args: { geog: unknown; maxchars?: number }; Returns: string }
        | { Args: { geom: unknown; maxchars?: number }; Returns: string };
      st_geomcollfromtext: { Args: { "": string }; Returns: unknown };
      st_geometricmedian: {
        Args: {
          fail_if_not_converged?: boolean;
          g: unknown;
          max_iter?: number;
          tolerance?: number;
        };
        Returns: unknown;
      };
      st_geometryfromtext: { Args: { "": string }; Returns: unknown };
      st_geomfromewkt: { Args: { "": string }; Returns: unknown };
      st_geomfromgeojson:
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": string }; Returns: unknown };
      st_geomfromgml: { Args: { "": string }; Returns: unknown };
      st_geomfromkml: { Args: { "": string }; Returns: unknown };
      st_geomfrommarc21: { Args: { marc21xml: string }; Returns: unknown };
      st_geomfromtext: { Args: { "": string }; Returns: unknown };
      st_gmltosql: { Args: { "": string }; Returns: unknown };
      st_hasarc: { Args: { geometry: unknown }; Returns: boolean };
      st_hausdorffdistance: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_hexagon: {
        Args: {
          cell_i: number;
          cell_j: number;
          origin?: unknown;
          size: number;
        };
        Returns: unknown;
      };
      st_hexagongrid: {
        Args: { bounds: unknown; size: number };
        Returns: Record<string, unknown>[];
      };
      st_interpolatepoint: {
        Args: { line: unknown; point: unknown };
        Returns: number;
      };
      st_intersection: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number };
        Returns: unknown;
      };
      st_intersects:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      st_isvaliddetail: {
        Args: { flags?: number; geom: unknown };
        Returns: Database["public"]["CompositeTypes"]["valid_detail"];
        SetofOptions: {
          from: "*";
          to: "valid_detail";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      st_length:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number };
      st_letters: { Args: { font?: Json; letters: string }; Returns: unknown };
      st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown };
        Returns: number;
      };
      st_linefromencodedpolyline: {
        Args: { nprecision?: number; txtin: string };
        Returns: unknown;
      };
      st_linefromtext: { Args: { "": string }; Returns: unknown };
      st_linelocatepoint: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_linetocurve: { Args: { geometry: unknown }; Returns: unknown };
      st_locatealong: {
        Args: { geometry: unknown; leftrightoffset?: number; measure: number };
        Returns: unknown;
      };
      st_locatebetween: {
        Args: {
          frommeasure: number;
          geometry: unknown;
          leftrightoffset?: number;
          tomeasure: number;
        };
        Returns: unknown;
      };
      st_locatebetweenelevations: {
        Args: { fromelevation: number; geometry: unknown; toelevation: number };
        Returns: unknown;
      };
      st_longestline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_makebox2d: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_makeline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_makevalid: {
        Args: { geom: unknown; params: string };
        Returns: unknown;
      };
      st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: number;
      };
      st_minimumboundingcircle: {
        Args: { inputgeom: unknown; segs_per_quarter?: number };
        Returns: unknown;
      };
      st_mlinefromtext: { Args: { "": string }; Returns: unknown };
      st_mpointfromtext: { Args: { "": string }; Returns: unknown };
      st_mpolyfromtext: { Args: { "": string }; Returns: unknown };
      st_multilinestringfromtext: { Args: { "": string }; Returns: unknown };
      st_multipointfromtext: { Args: { "": string }; Returns: unknown };
      st_multipolygonfromtext: { Args: { "": string }; Returns: unknown };
      st_node: { Args: { g: unknown }; Returns: unknown };
      st_normalize: { Args: { geom: unknown }; Returns: unknown };
      st_offsetcurve: {
        Args: { distance: number; line: unknown; params?: string };
        Returns: unknown;
      };
      st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_overlaps: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_perimeter: {
        Args: { geog: unknown; use_spheroid?: boolean };
        Returns: number;
      };
      st_pointfromtext: { Args: { "": string }; Returns: unknown };
      st_pointm: {
        Args: {
          mcoordinate: number;
          srid?: number;
          xcoordinate: number;
          ycoordinate: number;
        };
        Returns: unknown;
      };
      st_pointz: {
        Args: {
          srid?: number;
          xcoordinate: number;
          ycoordinate: number;
          zcoordinate: number;
        };
        Returns: unknown;
      };
      st_pointzm: {
        Args: {
          mcoordinate: number;
          srid?: number;
          xcoordinate: number;
          ycoordinate: number;
          zcoordinate: number;
        };
        Returns: unknown;
      };
      st_polyfromtext: { Args: { "": string }; Returns: unknown };
      st_polygonfromtext: { Args: { "": string }; Returns: unknown };
      st_project: {
        Args: { azimuth: number; distance: number; geog: unknown };
        Returns: unknown;
      };
      st_quantizecoordinates: {
        Args: {
          g: unknown;
          prec_m?: number;
          prec_x: number;
          prec_y?: number;
          prec_z?: number;
        };
        Returns: unknown;
      };
      st_reduceprecision: {
        Args: { geom: unknown; gridsize: number };
        Returns: unknown;
      };
      st_relate: { Args: { geom1: unknown; geom2: unknown }; Returns: string };
      st_removerepeatedpoints: {
        Args: { geom: unknown; tolerance?: number };
        Returns: unknown;
      };
      st_segmentize: {
        Args: { geog: unknown; max_segment_length: number };
        Returns: unknown;
      };
      st_setsrid:
        | { Args: { geog: unknown; srid: number }; Returns: unknown }
        | { Args: { geom: unknown; srid: number }; Returns: unknown };
      st_sharedpaths: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_shortestline: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_simplifypolygonhull: {
        Args: { geom: unknown; is_outer?: boolean; vertex_fraction: number };
        Returns: unknown;
      };
      st_split: { Args: { geom1: unknown; geom2: unknown }; Returns: unknown };
      st_square: {
        Args: {
          cell_i: number;
          cell_j: number;
          origin?: unknown;
          size: number;
        };
        Returns: unknown;
      };
      st_squaregrid: {
        Args: { bounds: unknown; size: number };
        Returns: Record<string, unknown>[];
      };
      st_srid:
        | { Args: { geog: unknown }; Returns: number }
        | { Args: { geom: unknown }; Returns: number };
      st_subdivide: {
        Args: { geom: unknown; gridsize?: number; maxvertices?: number };
        Returns: unknown[];
      };
      st_swapordinates: {
        Args: { geom: unknown; ords: unknown };
        Returns: unknown;
      };
      st_symdifference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number };
        Returns: unknown;
      };
      st_symmetricdifference: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: unknown;
      };
      st_tileenvelope: {
        Args: {
          bounds?: unknown;
          margin?: number;
          x: number;
          y: number;
          zoom: number;
        };
        Returns: unknown;
      };
      st_touches: {
        Args: { geom1: unknown; geom2: unknown };
        Returns: boolean;
      };
      st_transform:
        | {
            Args: { from_proj: string; geom: unknown; to_proj: string };
            Returns: unknown;
          }
        | {
            Args: { from_proj: string; geom: unknown; to_srid: number };
            Returns: unknown;
          }
        | { Args: { geom: unknown; to_proj: string }; Returns: unknown };
      st_triangulatepolygon: { Args: { g1: unknown }; Returns: unknown };
      st_union:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
        | {
            Args: { geom1: unknown; geom2: unknown; gridsize: number };
            Returns: unknown;
          };
      st_voronoilines: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number };
        Returns: unknown;
      };
      st_voronoipolygons: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number };
        Returns: unknown;
      };
      st_within: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean };
      st_wkbtosql: { Args: { wkb: string }; Returns: unknown };
      st_wkttosql: { Args: { "": string }; Returns: unknown };
      st_wrapx: {
        Args: { geom: unknown; move: number; wrap: number };
        Returns: unknown;
      };
      start_transit_for_execution: {
        Args: { p_org_id: string; p_set_id: string };
        Returns: boolean;
      };
      submit_contract_for_approval:
        | {
            Args: {
              p_contract_id: string;
              p_expires_at: string;
              p_token: string;
              p_token_id: string;
            };
            Returns: undefined;
          }
        | {
            Args: {
              p_contract_id: string;
              p_expected_version?: number;
              p_expires_at: string;
              p_token: string;
              p_token_id: string;
            };
            Returns: undefined;
          };
      super_admin_add_org_admin:
        | {
            Args: {
              p_email: string;
              p_expires_at: string;
              p_invitation_id: string;
              p_invited_by: string;
              p_org_id: string;
              p_token: string;
            };
            Returns: undefined;
          }
        | {
            Args: {
              p_email: string;
              p_expires_at: string;
              p_invitation_id: string;
              p_invited_by: string;
              p_org_id: string;
              p_reason?: string;
              p_token: string;
            };
            Returns: undefined;
          };
      super_admin_archive_organization: {
        Args: { p_org_id: string; p_reason: string; p_super_admin_id: string };
        Returns: undefined;
      };
      super_admin_audit_resend_invitation: {
        Args: { p_email: string; p_org_id: string; p_reason: string };
        Returns: undefined;
      };
      super_admin_check_cnpj_exists: {
        Args: { p_cnpj: string };
        Returns: boolean;
      };
      super_admin_create_organization: {
        Args: {
          p_allowed_domains?: string[];
          p_billing_day?: number;
          p_capabilities?: Json;
          p_cnpj: string;
          p_contact_email?: string;
          p_currency_code: string;
          p_dwell_time_seconds?: number;
          p_external_id?: string;
          p_legal_name: string;
          p_max_active_contracts: number;
          p_max_vehicles: number;
          p_organization_type?: string;
          p_plan_type: string;
          p_reason?: string;
          p_super_admin_user_id: string;
          p_timezone: string;
          p_tool_cost_cents?: number;
          p_trade_name: string;
        };
        Returns: {
          org_id: string;
          plaintext_secret: string;
        }[];
      };
      super_admin_get_org_members: {
        Args: { p_org_id: string };
        Returns: {
          email: string;
          invited_at: string;
          is_active: boolean;
          last_sign_in: string;
          role: string;
          status: string;
          token: string;
          user_id: string;
        }[];
      };
      super_admin_invite_first_admin: {
        Args: {
          p_email: string;
          p_expires_at: string;
          p_invitation_id: string;
          p_invited_by: string;
          p_org_id: string;
          p_role: string;
          p_token: string;
        };
        Returns: undefined;
      };
      super_admin_revoke_invitation: {
        Args: {
          p_email: string;
          p_org_id: string;
          p_reason?: string;
          p_super_admin_id: string;
        };
        Returns: undefined;
      };
      super_admin_toggle_member_status: {
        Args: { p_is_active: boolean; p_org_id: string; p_user_id: string };
        Returns: undefined;
      };
      super_admin_unarchive_organization: {
        Args: { p_org_id: string; p_reason: string; p_super_admin_id: string };
        Returns: undefined;
      };
      super_admin_update_allowed_domains: {
        Args: {
          p_allowed_domains: string[];
          p_org_id: string;
          p_reason?: string;
          p_super_admin_user_id: string;
        };
        Returns: undefined;
      };
      super_admin_update_organization_quota: {
        Args: {
          p_billing_day?: number;
          p_capabilities?: Json;
          p_contact_email?: string;
          p_dwell_time_seconds?: number;
          p_expected_updated_at?: string;
          p_external_id?: string;
          p_legal_name?: string;
          p_new_max_contracts: number;
          p_new_max_vehicles: number;
          p_new_plan_type: string;
          p_org_id: string;
          p_organization_type?: string;
          p_reason?: string;
          p_super_admin_user_id: string;
          p_tool_cost_cents?: number;
          p_trade_name?: string;
        };
        Returns: undefined;
      };
      test_archive_org_for_e2e: {
        Args: { p_org_id: string };
        Returns: undefined;
      };
      test_cleanup_forensic_data: {
        Args: { p_org_id: string };
        Returns: undefined;
      };
      test_cleanup_system_audit_log: {
        Args: { p_org_ids: string[] };
        Returns: undefined;
      };
      test_get_user_banned_until: {
        Args: { p_user_id: string };
        Returns: string;
      };
      test_tamper_raw_telemetry_payload: {
        Args: { p_new_payload: Json; p_record_id: string };
        Returns: undefined;
      };
      try_acquire_idempotency_key: {
        Args: {
          p_command_path: string;
          p_id: string;
          p_organization_id: string;
          p_stale_threshold_min?: number;
          p_user_id: string;
        };
        Returns: Json;
      };
      unlockrows: { Args: { "": string }; Returns: number };
      update_contractual_rule: {
        Args: {
          p_contract_id: string;
          p_evaluation_order: number;
          p_new_config: Json;
          p_now_utc?: string;
          p_old_rule_id: string;
          p_rule_type: Database["public"]["Enums"]["sla_rule_type"];
        };
        Returns: string;
      };
      update_justification_status_with_audit: {
        Args: {
          p_evidence_urls: string[];
          p_expected_status: string;
          p_justification_id: string;
          p_new_status: string;
          p_org_id: string;
          p_resolution_notes: string;
        };
        Returns: number;
      };
      update_member_role: {
        Args: { p_new_role: string; p_target_user_id: string };
        Returns: undefined;
      };
      updategeometrysrid: {
        Args: {
          catalogn_name: string;
          column_name: string;
          new_srid_in: number;
          schema_name: string;
          table_name: string;
        };
        Returns: string;
      };
      use_justification_token: {
        Args: { p_category: string; p_description: string; p_token: string };
        Returns: string;
      };
      verify_forensic_evidence: {
        Args: { p_ledger_entry_id: string; p_organization_id: string };
        Returns: Json;
      };
      vp_haversine_meters: {
        Args: { lat1: number; lat2: number; lon1: number; lon2: number };
        Returns: number;
      };
    };
    Enums: {
      sla_rule_type:
        | "MAX_TOLERANCE_DELAY"
        | "MAX_EVIDENCE_GAP"
        | "MIN_GEOFENCE_COVERAGE"
        | "NO_SHOW_PENALTY"
        | "REQUIRED_EVIDENCE";
    };
    CompositeTypes: {
      geometry_dump: {
        path: number[] | null;
        geom: unknown;
      };
      valid_detail: {
        valid: boolean | null;
        reason: string | null;
        location: unknown;
      };
    };
  };
  storage: {
    Tables: {
      buckets: {
        Row: {
          allowed_mime_types: string[] | null;
          avif_autodetection: boolean | null;
          created_at: string | null;
          file_size_limit: number | null;
          id: string;
          name: string;
          owner: string | null;
          owner_id: string | null;
          public: boolean | null;
          type: Database["storage"]["Enums"]["buckettype"];
          updated_at: string | null;
        };
        Insert: {
          allowed_mime_types?: string[] | null;
          avif_autodetection?: boolean | null;
          created_at?: string | null;
          file_size_limit?: number | null;
          id: string;
          name: string;
          owner?: string | null;
          owner_id?: string | null;
          public?: boolean | null;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string | null;
        };
        Update: {
          allowed_mime_types?: string[] | null;
          avif_autodetection?: boolean | null;
          created_at?: string | null;
          file_size_limit?: number | null;
          id?: string;
          name?: string;
          owner?: string | null;
          owner_id?: string | null;
          public?: boolean | null;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string | null;
        };
        Relationships: [];
      };
      buckets_analytics: {
        Row: {
          created_at: string;
          deleted_at: string | null;
          format: string;
          id: string;
          name: string;
          type: Database["storage"]["Enums"]["buckettype"];
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          deleted_at?: string | null;
          format?: string;
          id?: string;
          name: string;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          deleted_at?: string | null;
          format?: string;
          id?: string;
          name?: string;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string;
        };
        Relationships: [];
      };
      buckets_vectors: {
        Row: {
          created_at: string;
          id: string;
          type: Database["storage"]["Enums"]["buckettype"];
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          id: string;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          type?: Database["storage"]["Enums"]["buckettype"];
          updated_at?: string;
        };
        Relationships: [];
      };
      iceberg_namespaces: {
        Row: {
          bucket_name: string;
          catalog_id: string;
          created_at: string;
          id: string;
          metadata: Json;
          name: string;
          updated_at: string;
        };
        Insert: {
          bucket_name: string;
          catalog_id: string;
          created_at?: string;
          id?: string;
          metadata?: Json;
          name: string;
          updated_at?: string;
        };
        Update: {
          bucket_name?: string;
          catalog_id?: string;
          created_at?: string;
          id?: string;
          metadata?: Json;
          name?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "iceberg_namespaces_catalog_id_fkey";
            columns: ["catalog_id"];
            isOneToOne: false;
            referencedRelation: "buckets_analytics";
            referencedColumns: ["id"];
          },
        ];
      };
      iceberg_tables: {
        Row: {
          bucket_name: string;
          catalog_id: string;
          created_at: string;
          id: string;
          location: string;
          name: string;
          namespace_id: string;
          remote_table_id: string | null;
          shard_id: string | null;
          shard_key: string | null;
          updated_at: string;
        };
        Insert: {
          bucket_name: string;
          catalog_id: string;
          created_at?: string;
          id?: string;
          location: string;
          name: string;
          namespace_id: string;
          remote_table_id?: string | null;
          shard_id?: string | null;
          shard_key?: string | null;
          updated_at?: string;
        };
        Update: {
          bucket_name?: string;
          catalog_id?: string;
          created_at?: string;
          id?: string;
          location?: string;
          name?: string;
          namespace_id?: string;
          remote_table_id?: string | null;
          shard_id?: string | null;
          shard_key?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "iceberg_tables_catalog_id_fkey";
            columns: ["catalog_id"];
            isOneToOne: false;
            referencedRelation: "buckets_analytics";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "iceberg_tables_namespace_id_fkey";
            columns: ["namespace_id"];
            isOneToOne: false;
            referencedRelation: "iceberg_namespaces";
            referencedColumns: ["id"];
          },
        ];
      };
      migrations: {
        Row: {
          executed_at: string | null;
          hash: string;
          id: number;
          name: string;
        };
        Insert: {
          executed_at?: string | null;
          hash: string;
          id: number;
          name: string;
        };
        Update: {
          executed_at?: string | null;
          hash?: string;
          id?: number;
          name?: string;
        };
        Relationships: [];
      };
      objects: {
        Row: {
          bucket_id: string | null;
          created_at: string | null;
          id: string;
          last_accessed_at: string | null;
          metadata: Json | null;
          name: string | null;
          owner: string | null;
          owner_id: string | null;
          path_tokens: string[] | null;
          updated_at: string | null;
          user_metadata: Json | null;
          version: string | null;
        };
        Insert: {
          bucket_id?: string | null;
          created_at?: string | null;
          id?: string;
          last_accessed_at?: string | null;
          metadata?: Json | null;
          name?: string | null;
          owner?: string | null;
          owner_id?: string | null;
          path_tokens?: string[] | null;
          updated_at?: string | null;
          user_metadata?: Json | null;
          version?: string | null;
        };
        Update: {
          bucket_id?: string | null;
          created_at?: string | null;
          id?: string;
          last_accessed_at?: string | null;
          metadata?: Json | null;
          name?: string | null;
          owner?: string | null;
          owner_id?: string | null;
          path_tokens?: string[] | null;
          updated_at?: string | null;
          user_metadata?: Json | null;
          version?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "objects_bucketId_fkey";
            columns: ["bucket_id"];
            isOneToOne: false;
            referencedRelation: "buckets";
            referencedColumns: ["id"];
          },
        ];
      };
      s3_multipart_uploads: {
        Row: {
          bucket_id: string;
          created_at: string;
          id: string;
          in_progress_size: number;
          key: string;
          metadata: Json | null;
          owner_id: string | null;
          upload_signature: string;
          user_metadata: Json | null;
          version: string;
        };
        Insert: {
          bucket_id: string;
          created_at?: string;
          id: string;
          in_progress_size?: number;
          key: string;
          metadata?: Json | null;
          owner_id?: string | null;
          upload_signature: string;
          user_metadata?: Json | null;
          version: string;
        };
        Update: {
          bucket_id?: string;
          created_at?: string;
          id?: string;
          in_progress_size?: number;
          key?: string;
          metadata?: Json | null;
          owner_id?: string | null;
          upload_signature?: string;
          user_metadata?: Json | null;
          version?: string;
        };
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_bucket_id_fkey";
            columns: ["bucket_id"];
            isOneToOne: false;
            referencedRelation: "buckets";
            referencedColumns: ["id"];
          },
        ];
      };
      s3_multipart_uploads_parts: {
        Row: {
          bucket_id: string;
          created_at: string;
          etag: string;
          id: string;
          key: string;
          owner_id: string | null;
          part_number: number;
          size: number;
          upload_id: string;
          version: string;
        };
        Insert: {
          bucket_id: string;
          created_at?: string;
          etag: string;
          id?: string;
          key: string;
          owner_id?: string | null;
          part_number: number;
          size?: number;
          upload_id: string;
          version: string;
        };
        Update: {
          bucket_id?: string;
          created_at?: string;
          etag?: string;
          id?: string;
          key?: string;
          owner_id?: string | null;
          part_number?: number;
          size?: number;
          upload_id?: string;
          version?: string;
        };
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_parts_bucket_id_fkey";
            columns: ["bucket_id"];
            isOneToOne: false;
            referencedRelation: "buckets";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "s3_multipart_uploads_parts_upload_id_fkey";
            columns: ["upload_id"];
            isOneToOne: false;
            referencedRelation: "s3_multipart_uploads";
            referencedColumns: ["id"];
          },
        ];
      };
      vector_indexes: {
        Row: {
          bucket_id: string;
          created_at: string;
          data_type: string;
          dimension: number;
          distance_metric: string;
          id: string;
          metadata_configuration: Json | null;
          name: string;
          updated_at: string;
        };
        Insert: {
          bucket_id: string;
          created_at?: string;
          data_type: string;
          dimension: number;
          distance_metric: string;
          id?: string;
          metadata_configuration?: Json | null;
          name: string;
          updated_at?: string;
        };
        Update: {
          bucket_id?: string;
          created_at?: string;
          data_type?: string;
          dimension?: number;
          distance_metric?: string;
          id?: string;
          metadata_configuration?: Json | null;
          name?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "vector_indexes_bucket_id_fkey";
            columns: ["bucket_id"];
            isOneToOne: false;
            referencedRelation: "buckets_vectors";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      allow_any_operation: {
        Args: { expected_operations: string[] };
        Returns: boolean;
      };
      allow_only_operation: {
        Args: { expected_operation: string };
        Returns: boolean;
      };
      can_insert_object: {
        Args: { bucketid: string; metadata: Json; name: string; owner: string };
        Returns: undefined;
      };
      extension: { Args: { name: string }; Returns: string };
      filename: { Args: { name: string }; Returns: string };
      foldername: { Args: { name: string }; Returns: string[] };
      get_common_prefix: {
        Args: { p_delimiter: string; p_key: string; p_prefix: string };
        Returns: string;
      };
      get_size_by_bucket: {
        Args: never;
        Returns: {
          bucket_id: string;
          size: number;
        }[];
      };
      list_multipart_uploads_with_delimiter: {
        Args: {
          bucket_id: string;
          delimiter_param: string;
          max_keys?: number;
          next_key_token?: string;
          next_upload_token?: string;
          prefix_param: string;
        };
        Returns: {
          created_at: string;
          id: string;
          key: string;
        }[];
      };
      list_objects_with_delimiter: {
        Args: {
          _bucket_id: string;
          delimiter_param: string;
          max_keys?: number;
          next_token?: string;
          prefix_param: string;
          sort_order?: string;
          start_after?: string;
        };
        Returns: {
          created_at: string;
          id: string;
          last_accessed_at: string;
          metadata: Json;
          name: string;
          updated_at: string;
        }[];
      };
      operation: { Args: never; Returns: string };
      search: {
        Args: {
          bucketname: string;
          levels?: number;
          limits?: number;
          offsets?: number;
          prefix: string;
          search?: string;
          sortcolumn?: string;
          sortorder?: string;
        };
        Returns: {
          created_at: string;
          id: string;
          last_accessed_at: string;
          metadata: Json;
          name: string;
          updated_at: string;
        }[];
      };
      search_by_timestamp: {
        Args: {
          p_bucket_id: string;
          p_level: number;
          p_limit: number;
          p_prefix: string;
          p_sort_column: string;
          p_sort_column_after: string;
          p_sort_order: string;
          p_start_after: string;
        };
        Returns: {
          created_at: string;
          id: string;
          key: string;
          last_accessed_at: string;
          metadata: Json;
          name: string;
          updated_at: string;
        }[];
      };
      search_v2: {
        Args: {
          bucket_name: string;
          levels?: number;
          limits?: number;
          prefix: string;
          sort_column?: string;
          sort_column_after?: string;
          sort_order?: string;
          start_after?: string;
        };
        Returns: {
          created_at: string;
          id: string;
          key: string;
          last_accessed_at: string;
          metadata: Json;
          name: string;
          updated_at: string;
        }[];
      };
    };
    Enums: {
      buckettype: "STANDARD" | "ANALYTICS" | "VECTOR";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      sla_rule_type: [
        "MAX_TOLERANCE_DELAY",
        "MAX_EVIDENCE_GAP",
        "MIN_GEOFENCE_COVERAGE",
        "NO_SHOW_PENALTY",
        "REQUIRED_EVIDENCE",
      ],
    },
  },
  storage: {
    Enums: {
      buckettype: ["STANDARD", "ANALYTICS", "VECTOR"],
    },
  },
} as const;
