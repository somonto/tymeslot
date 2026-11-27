alias Tymeslot.Repo
alias Tymeslot.Auth.UserSchema
alias Tymeslot.Profiles.ProfileSchema
alias Tymeslot.Availability.{AvailabilityScheduleSchema, WeeklyAvailabilitySchema}
alias Tymeslot.MeetingTypes.MeetingTypeSchema
user = Repo.insert!(%UserSchema{email: "probe@example.invalid", name: "Niklas Aschauer", verified_at: DateTime.utc_now(:second), provider: "email"})
profile = Repo.insert!(%ProfileSchema{user_id: user.id, username: "probe", full_name: "Niklas Aschauer", booking_theme: "1", timezone: "Europe/Vienna",
  booking_text_enabled: true, booking_greeting: "Ihr Berater ist Niklas Aschauer.", booking_page_published_at: DateTime.utc_now(:second)})
schedule = Repo.insert!(%AvailabilityScheduleSchema{profile_id: profile.id, name: "Standard", is_default: true, advance_booking_days: 30, min_advance_hours: 0, buffer_before_minutes: 0, buffer_after_minutes: 0})
for d <- 1..7, do: Repo.insert!(%WeeklyAvailabilitySchema{schedule_id: schedule.id, day_of_week: d, is_available: true, start_time: ~T[09:00:00], end_time: ~T[17:00:00]})
mt = Repo.insert!(%MeetingTypeSchema{user_id: user.id, name: "Erstgespräch", description: "", duration_minutes: 15, icon: "hero-bolt", is_active: true, allow_video: false, sort_order: 0})
{:ok, _} = Tymeslot.MeetingTypes.update_meeting_type(mt, %{"custom_fields" => [
  %{"id" => "cf-company", "type" => "short_text", "label" => "Name des Unternehmens", "required" => true, "position" => 0},
  %{"id" => "cf-phone", "type" => "phone", "label" => "Telefonnummer", "required" => true, "position" => 1}]})
IO.puts("SEED_OK #{profile.username} #{mt.slug}")
