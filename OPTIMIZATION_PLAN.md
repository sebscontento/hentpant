# Supabase Integration Optimization Plan

**Date**: March 28, 2026  
**Status**: In Progress

## Current State Analysis

### Database Performance Issues
- ✅ Basic indexes exist: `listings_status_idx`, `listings_giver_idx`, `listings_created_idx`, `ratings_to_user_idx`
- ❌ Missing index on `listings.collector_id` (used in filtering for claimed listings)
- ❌ Missing index on `profiles.moderator_request_status` (used for admin flows)
- ❌ Missing index on `reports.target` and `reports.created_at` (used for staff filtering)

### Query Optimization Gaps
- ❌ `loadAllFromRemote()` loads ALL rows from profiles, listings, ratings (no limits/pagination)
- ⚠️  Queries don't use PostgREST select() to limit fields being transferred
- ❌ No pagination for large datasets
- ❌ Full reload on every mutation (claim, rating, etc.) instead of incremental updates

### Configuration Issues
- ❌ Connection pooling disabled in `config.toml` (max_client_conn = 100 could saturate)
- ⚠️  No compression configured for API responses

### Feature Gaps
- ❌ No real-time subscriptions (currently polling via full refresh)
- ❌ No client-side caching strategy
- ❌ RPC functions return void - could return updated rows to avoid extra queries

## Optimization Tasks

### Phase 1: Database Indexes (Quick Win - ~15 min)
- [ ] Add `listings.collector_id` index
- [ ] Add `profiles.moderator_request_status` index
- [ ] Add `reports` compound index on `(target, created_at)`
- [ ] Add composite index for common filter combinations

### Phase 2: Configuration (5 min)
- [ ] Enable connection pooling with optimal settings for mobile app
- [ ] Add response compression

### Phase 3: Query Optimization (30 min)
- [ ] Implement selective field loading in PostgREST queries
- [ ] Add pagination support for listings
- [ ] Optimize profile loading to only fetch when needed
- [ ] Replace full reloads with targeted updates after mutations

### Phase 4: Caching Strategy (45 min)
- [ ] Implement in-memory profile cache with TTL
- [ ] Add listing batch caching
- [ ] Cache user's own profile locally
- [ ] Smart invalidation on mutations

### Phase 5: Real-time Integration (60 min)
- [ ] Add Realtime subscriptions for listings feed
- [ ] Add Realtime subscriptions for rating updates
- [ ] Add Realtime subscriptions for reports (staff only)
- [ ] Graceful degradation if subscriptions fail

### Phase 6: RPC Optimization (20 min)
- [ ] Modify RPC functions to return updated rows
- [ ] Reduce post-mutation queries

## Performance Targets
- **Initial load**: < 2 seconds
- **Refresh**: < 1 second
- **Mutation response**: < 500ms
- **Database queries**: < 100ms each
- **Network overhead**: Reduce by 40-60% with selective fields

## Implementation Steps
1. ✅ Create optimization migration file
2. ✅ Update config.toml for pooling
3. ✅ Implement selective field loading in AppState
4. ✅ Add pagination helper functions
5. ✅ Implement caching layer
6. ✅ Add Realtime subscriptions
7. ✅ Refactor mutations for efficiency
