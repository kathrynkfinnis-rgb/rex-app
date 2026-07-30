export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      check_ins: {
        Row: {
          created_at: string
          id: string
          item_id: string
          note: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_id: string
          note?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          item_id?: string
          note?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "check_ins_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      creator_follows: {
        Row: {
          created_at: string
          creator_id: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          creator_id: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          creator_id?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "creator_follows_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "creators"
            referencedColumns: ["id"]
          },
        ]
      }
      creators: {
        Row: {
          color: string
          created_at: string
          emoji: string | null
          id: string
          name: string
          slug: string
        }
        Insert: {
          color: string
          created_at?: string
          emoji?: string | null
          id?: string
          name: string
          slug: string
        }
        Update: {
          color?: string
          created_at?: string
          emoji?: string | null
          id?: string
          name?: string
          slug?: string
        }
        Relationships: []
      }
      feedback: {
        Row: {
          created_at: string
          id: string
          is_anonymous: boolean
          kind: string
          message: string
          page: string | null
          status: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_anonymous?: boolean
          kind?: string
          message: string
          page?: string | null
          status?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_anonymous?: boolean
          kind?: string
          message?: string
          page?: string | null
          status?: string
          user_id?: string | null
        }
        Relationships: []
      }
      friendships: {
        Row: {
          addressee_id: string
          created_at: string
          id: string
          requester_id: string
          status: Database["public"]["Enums"]["friendship_status"]
          updated_at: string
        }
        Insert: {
          addressee_id: string
          created_at?: string
          id?: string
          requester_id: string
          status?: Database["public"]["Enums"]["friendship_status"]
          updated_at?: string
        }
        Update: {
          addressee_id?: string
          created_at?: string
          id?: string
          requester_id?: string
          status?: Database["public"]["Enums"]["friendship_status"]
          updated_at?: string
        }
        Relationships: []
      }
      group_members: {
        Row: {
          created_at: string
          group_id: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          group_id: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          group_id?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "group_members_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
        ]
      }
      group_shares: {
        Row: {
          created_at: string
          group_id: string
          id: string
          note: string | null
          recommendation_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          group_id: string
          id?: string
          note?: string | null
          recommendation_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          group_id?: string
          id?: string
          note?: string | null
          recommendation_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "group_shares_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "group_shares_recommendation_id_fkey"
            columns: ["recommendation_id"]
            isOneToOne: false
            referencedRelation: "recommendations"
            referencedColumns: ["id"]
          },
        ]
      }
      groups: {
        Row: {
          created_at: string
          emoji: string | null
          id: string
          name: string
          owner_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          emoji?: string | null
          id?: string
          name: string
          owner_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          emoji?: string | null
          id?: string
          name?: string
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      hitlist_lists: {
        Row: {
          created_at: string
          emoji: string | null
          id: string
          item_type: string
          name: string
          user_id: string
          visibility: Database["public"]["Enums"]["list_visibility"]
        }
        Insert: {
          created_at?: string
          emoji?: string | null
          id?: string
          item_type: string
          name: string
          user_id: string
          visibility?: Database["public"]["Enums"]["list_visibility"]
        }
        Update: {
          created_at?: string
          emoji?: string | null
          id?: string
          item_type?: string
          name?: string
          user_id?: string
          visibility?: Database["public"]["Enums"]["list_visibility"]
        }
        Relationships: []
      }
      import_staging: {
        Row: {
          created_at: string
          id: string
          raw_creator: string | null
          raw_note: string | null
          raw_rating: number | null
          raw_title: string
          resolved_external_id: string | null
          resolved_external_source: string | null
          resolved_genre: string | null
          resolved_image_url: string | null
          resolved_item_id: string | null
          resolved_subtitle: string | null
          source: string
          status: string
          suggested_type: Database["public"]["Enums"]["item_type"] | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          raw_creator?: string | null
          raw_note?: string | null
          raw_rating?: number | null
          raw_title: string
          resolved_external_id?: string | null
          resolved_external_source?: string | null
          resolved_genre?: string | null
          resolved_image_url?: string | null
          resolved_item_id?: string | null
          resolved_subtitle?: string | null
          source: string
          status?: string
          suggested_type?: Database["public"]["Enums"]["item_type"] | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          raw_creator?: string | null
          raw_note?: string | null
          raw_rating?: number | null
          raw_title?: string
          resolved_external_id?: string | null
          resolved_external_source?: string | null
          resolved_genre?: string | null
          resolved_image_url?: string | null
          resolved_item_id?: string | null
          resolved_subtitle?: string | null
          source?: string
          status?: string
          suggested_type?: Database["public"]["Enums"]["item_type"] | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_staging_resolved_item_id_fkey"
            columns: ["resolved_item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      items: {
        Row: {
          address: string | null
          created_at: string
          external_id: string | null
          external_source: string | null
          genre: string | null
          id: string
          image_url: string | null
          lat: number | null
          lng: number | null
          recipe_text: string | null
          subtitle: string | null
          title: string
          type: Database["public"]["Enums"]["item_type"]
        }
        Insert: {
          address?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          genre?: string | null
          id?: string
          image_url?: string | null
          lat?: number | null
          lng?: number | null
          recipe_text?: string | null
          subtitle?: string | null
          title: string
          type: Database["public"]["Enums"]["item_type"]
        }
        Update: {
          address?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          genre?: string | null
          id?: string
          image_url?: string | null
          lat?: number | null
          lng?: number | null
          recipe_text?: string | null
          subtitle?: string | null
          title?: string
          type?: Database["public"]["Enums"]["item_type"]
        }
        Relationships: []
      }
      list_collaborators: {
        Row: {
          added_by: string
          created_at: string
          id: string
          list_id: string
          user_id: string
        }
        Insert: {
          added_by: string
          created_at?: string
          id?: string
          list_id: string
          user_id: string
        }
        Update: {
          added_by?: string
          created_at?: string
          id?: string
          list_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "list_collaborators_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "hitlist_lists"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          blast_comment: boolean
          blast_new: boolean
          created_at: string
          email_enabled: boolean
          friend_accepted: boolean
          friend_new_rec: boolean
          friend_request: boolean
          mention: boolean
          rec_comment: boolean
          rec_like: boolean
          rec_saved: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          blast_comment?: boolean
          blast_new?: boolean
          created_at?: string
          email_enabled?: boolean
          friend_accepted?: boolean
          friend_new_rec?: boolean
          friend_request?: boolean
          mention?: boolean
          rec_comment?: boolean
          rec_like?: boolean
          rec_saved?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          blast_comment?: boolean
          blast_new?: boolean
          created_at?: string
          email_enabled?: boolean
          friend_accepted?: boolean
          friend_new_rec?: boolean
          friend_request?: boolean
          mention?: boolean
          rec_comment?: boolean
          rec_like?: boolean
          rec_saved?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          actor_id: string | null
          created_at: string
          data: Json
          entity_id: string | null
          entity_type: string | null
          id: string
          read_at: string | null
          type: string
          user_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          data?: Json
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          read_at?: string | null
          type: string
          user_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          data?: Json
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          read_at?: string | null
          type?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          display_name: string | null
          id: string
          updated_at: string
          username: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          display_name?: string | null
          id: string
          updated_at?: string
          username: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          display_name?: string | null
          id?: string
          updated_at?: string
          username?: string
        }
        Relationships: []
      }
      recommendation_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          recommendation_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          recommendation_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          recommendation_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recommendation_comments_recommendation_id_fkey"
            columns: ["recommendation_id"]
            isOneToOne: false
            referencedRelation: "recommendations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recommendation_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recommendation_likes: {
        Row: {
          created_at: string
          id: string
          recommendation_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          recommendation_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          recommendation_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recommendation_likes_recommendation_id_fkey"
            columns: ["recommendation_id"]
            isOneToOne: false
            referencedRelation: "recommendations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recommendation_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recommendations: {
        Row: {
          created_at: string
          creator_id: string | null
          id: string
          item_id: string
          note: string | null
          photo_url: string | null
          photo_urls: string[]
          rating: number
          tags: string[]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          creator_id?: string | null
          id?: string
          item_id: string
          note?: string | null
          photo_url?: string | null
          photo_urls?: string[]
          rating: number
          tags?: string[]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          creator_id?: string | null
          id?: string
          item_id?: string
          note?: string | null
          photo_url?: string | null
          photo_urls?: string[]
          rating?: number
          tags?: string[]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recommendations_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "creators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recommendations_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recommendations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      request_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          request_id: string
          suggested_item_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          request_id: string
          suggested_item_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          request_id?: string
          suggested_item_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_comments_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_comments_suggested_item_id_fkey"
            columns: ["suggested_item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_comments_user_id_profiles_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      requests: {
        Row: {
          created_at: string
          id: string
          note: string | null
          title: string
          type: Database["public"]["Enums"]["item_type"] | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          note?: string | null
          title: string
          type?: Database["public"]["Enums"]["item_type"] | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          note?: string | null
          title?: string
          type?: Database["public"]["Enums"]["item_type"] | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "requests_user_id_profiles_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_posts: {
        Row: {
          created_at: string
          id: string
          list_id: string | null
          recommendation_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          list_id?: string | null
          recommendation_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          list_id?: string | null
          recommendation_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_posts_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "hitlist_lists"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_posts_recommendation_id_fkey"
            columns: ["recommendation_id"]
            isOneToOne: false
            referencedRelation: "recommendations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      wants: {
        Row: {
          created_at: string
          id: string
          item_id: string
          list_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_id: string
          list_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          item_id?: string
          list_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wants_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wants_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "hitlist_lists"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_kpis_content: { Args: never; Returns: Json }
      admin_kpis_engagement: { Args: never; Returns: Json }
      admin_kpis_users: { Args: never; Returns: Json }
      are_friends: { Args: { _a: string; _b: string }; Returns: boolean }
      can_edit_list: {
        Args: { _list: string; _user: string }
        Returns: boolean
      }
      get_shared_recommendation: {
        Args: { rec_id: string }
        Returns: {
          author_avatar_url: string
          author_display_name: string
          author_username: string
          created_at: string
          id: string
          item_genre: string
          item_id: string
          item_image_url: string
          item_subtitle: string
          item_title: string
          item_type: string
          note: string
          photo_url: string
          photo_urls: string[]
          rating: number
        }[]
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_group_member: {
        Args: { _group: string; _user: string }
        Returns: boolean
      }
      is_group_owner: {
        Args: { _group: string; _user: string }
        Returns: boolean
      }
      is_list_owner: {
        Args: { _list: string; _user: string }
        Returns: boolean
      }
      notif_pref_enabled: {
        Args: { _type: string; _user: string }
        Returns: boolean
      }
      search_profiles_for: {
        Args: { _caller: string; _limit?: number; _query: string }
        Returns: {
          avatar_url: string
          display_name: string
          id: string
          username: string
        }[]
      }
      suggested_friends_for: {
        Args: { _caller: string; _limit?: number }
        Returns: {
          avatar_url: string
          display_name: string
          id: string
          mutual_count: number
          username: string
        }[]
      }
      top_rexxers_weekly: {
        Args: { _limit?: number }
        Returns: {
          avatar_url: string
          display_name: string
          rex_count: number
          user_id: string
          username: string
        }[]
      }
    }
    Enums: {
      app_role: "admin" | "moderator" | "user"
      friendship_status: "pending" | "accepted"
      item_type:
        | "place"
        | "book"
        | "movie"
        | "tv"
        | "recipe"
        | "podcast"
        | "event"
        | "other"
      list_visibility: "draft" | "friends" | "public"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "moderator", "user"],
      friendship_status: ["pending", "accepted"],
      item_type: [
        "place",
        "book",
        "movie",
        "tv",
        "recipe",
        "podcast",
        "event",
        "other",
      ],
      list_visibility: ["draft", "friends", "public"],
    },
  },
} as const
