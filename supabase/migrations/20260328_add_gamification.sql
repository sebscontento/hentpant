-- Gamification system for hentpant
-- Adds user stats, achievements, and points tracking

-- User stats table
CREATE TABLE IF NOT EXISTS user_stats (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_listings_posted INT NOT NULL DEFAULT 0,
    total_listings_collected INT NOT NULL DEFAULT 0,
    total_distance_meters NUMERIC NOT NULL DEFAULT 0,
    total_earnings_dkk NUMERIC NOT NULL DEFAULT 0,
    points INT NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    streak_days INT NOT NULL DEFAULT 0,
    last_active_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Achievements table
CREATE TABLE IF NOT EXISTS achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    unlocked_at TIMESTAMPTZ,
    points_awarded INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, type)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_achievements_user_id ON achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_achievements_type ON achievements(type);
CREATE INDEX IF NOT EXISTS idx_user_stats_points ON user_stats(points DESC);

-- Trigger to create user_stats row when profile is created
CREATE OR REPLACE FUNCTION create_user_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_stats (id)
    VALUES (NEW.id)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_profile_created ON profiles;
CREATE TRIGGER on_profile_created
    AFTER INSERT ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION create_user_stats();

-- Function to award points to a user
CREATE OR REPLACE FUNCTION award_points(p_user_id UUID, p_points INT, p_reason TEXT DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    new_points INT;
    new_level INT;
BEGIN
    UPDATE user_stats
    SET points = points + p_points,
        updated_at = NOW()
    WHERE id = p_user_id
    RETURNING points INTO new_points;

    -- Calculate new level (every 500 points per level)
    new_level := GREATEST(1, new_points / 500);

    UPDATE user_stats
    SET level = new_level,
        updated_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to unlock achievement
CREATE OR REPLACE FUNCTION unlock_achievement(p_user_id UUID, p_type TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_achievement_id UUID;
    v_points INT;
    v_already_exists BOOLEAN;
BEGIN
    -- Check if already unlocked
    SELECT EXISTS(
        SELECT 1 FROM achievements WHERE user_id = p_user_id AND type = p_type AND unlocked_at IS NOT NULL
    ) INTO v_already_exists;

    IF v_already_exists THEN
        RETURN FALSE;
    END IF;

    -- Get points for this achievement type
    CASE p_type
        WHEN 'firstListing' THEN v_points := 50;
        WHEN 'firstPickup' THEN v_points := 100;
        WHEN 'tenListings' THEN v_points := 250;
        WHEN 'tenPickups' THEN v_points := 500;
        WHEN 'fiftyPickups' THEN v_points := 2000;
        WHEN 'ecoWarrior' THEN v_points := 1000;
        WHEN 'nightOwl' THEN v_points := 75;
        WHEN 'weekendWarrior' THEN v_points := 150;
        WHEN 'quickCollector' THEN v_points := 100;
        WHEN 'generousGiver' THEN v_points := 750;
        ELSE v_points := 0;
    END CASE;

    -- Insert or update achievement
    INSERT INTO achievements (user_id, type, unlocked_at, points_awarded)
    VALUES (p_user_id, p_type, NOW(), v_points)
    ON CONFLICT (user_id, type) DO UPDATE
    SET unlocked_at = NOW(), points_awarded = v_points
    RETURNING id INTO v_achievement_id;

    -- Award points
    IF v_points > 0 THEN
        PERFORM award_points(p_user_id, v_points, 'Achievement: ' || p_type);
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update stats after listing completed
CREATE OR REPLACE FUNCTION process_gamification_on_listing_complete(
    p_listing_id UUID,
    p_giver_id UUID,
    p_collector_id UUID,
    p_distance_meters NUMERIC DEFAULT 0,
    p_bag_size TEXT DEFAULT 'medium'
)
RETURNS VOID AS $$
DECLARE
    v_earnings_dkk NUMERIC;
    v_listing_count INT;
    v_pickup_count INT;
BEGIN
    -- Calculate earnings based on bag size
    CASE p_bag_size
        WHEN 'small' THEN v_earnings_dkk := 15;
        WHEN 'medium' THEN v_earnings_dkk := 30;
        WHEN 'large' THEN v_earnings_dkk := 45;
        ELSE v_earnings_dkk := 25;
    END CASE;

    -- Update giver stats
    UPDATE user_stats
    SET total_listings_posted = total_listings_posted + 1,
        last_active_date = NOW(),
        updated_at = NOW()
    WHERE id = p_giver_id;

    -- Update collector stats
    UPDATE user_stats
    SET total_listings_collected = total_listings_collected + 1,
        total_distance_meters = total_distance_meters + p_distance_meters,
        total_earnings_dkk = total_earnings_dkk + v_earnings_dkk,
        last_active_date = NOW(),
        updated_at = NOW()
    WHERE id = p_collector_id;

    -- Award points for completing transaction
    PERFORM award_points(p_giver_id, 25, 'Listing completed');
    PERFORM award_points(p_collector_id, 50, 'Pickup completed');

    -- Check achievements for giver
    SELECT COUNT(*) INTO v_listing_count FROM listings WHERE giver_id = p_giver_id;
    IF v_listing_count >= 1 THEN
        PERFORM unlock_achievement(p_giver_id, 'firstListing');
    END IF;
    IF v_listing_count >= 10 THEN
        PERFORM unlock_achievement(p_giver_id, 'tenListings');
    END IF;
    IF v_listing_count >= 25 THEN
        PERFORM unlock_achievement(p_giver_id, 'generousGiver');
    END IF;

    -- Check achievements for collector
    SELECT COUNT(*) INTO v_pickup_count FROM listings
    WHERE collector_id = p_collector_id AND status = 'completed';
    IF v_pickup_count >= 1 THEN
        PERFORM unlock_achievement(p_collector_id, 'firstPickup');
    END IF;
    IF v_pickup_count >= 10 THEN
        PERFORM unlock_achievement(p_collector_id, 'tenPickups');
    END IF;
    IF v_pickup_count >= 50 THEN
        PERFORM unlock_achievement(p_collector_id, 'fiftyPickups');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row Level Security
ALTER TABLE user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;

-- Users can view their own stats
CREATE POLICY "Users can view own stats" ON user_stats
    FOR SELECT USING (auth.uid() = id);

-- Users can view their own achievements
CREATE POLICY "Users can view own achievements" ON achievements
    FOR SELECT USING (auth.uid() = user_id);

-- Users can view public leaderboard stats (points, level only)
CREATE POLICY "Users can view leaderboard" ON user_stats
    FOR SELECT USING (true);

-- Grant access
GRANT SELECT ON user_stats TO authenticated;
GRANT SELECT ON achievements TO authenticated;
GRANT EXECUTE ON FUNCTION award_points TO authenticated;
GRANT EXECUTE ON FUNCTION unlock_achievement TO authenticated;
GRANT EXECUTE ON FUNCTION process_gamification_on_listing_complete TO authenticated;
