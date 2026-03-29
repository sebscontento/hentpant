//
//  SupabaseClient.swift
//  hentpant
//
//  Shared Supabase client for Auth, PostgREST, Storage, and Realtime.
//

import Foundation
import Supabase

/// Project URL and anon key: **Project Settings → API** in the Supabase dashboard.
enum SupabaseProject {
    static let url = URL(string: "https://jfyuhjxmjbhxtfgtfkhd.supabase.co")!
    /// Publishable (anon) key — safe to ship in the app; protect data with Row Level Security.
    static let anonKey = "sb_publishable_pRB2ct6_Jc_RcPizYDO5Tw_Df-41O5V"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseProject.url,
    supabaseKey: SupabaseProject.anonKey
)
