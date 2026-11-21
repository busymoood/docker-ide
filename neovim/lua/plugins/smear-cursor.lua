return {
  "sphamba/smear-cursor.nvim",
  opts = {
    -- Adjust to control how long the cursor trail lasts (lower = faster)
    stiffness = 0.8,
    -- Adjust the trail effect intensity
    trailing_stiffness = 0.5,
    -- Distance threshold (in lines) to trigger the animation
    distance_stop_animating = 0.1,
    -- Hide the smear during rapid typing to prevent lag
    hide_target_hack = false,
  },
}
