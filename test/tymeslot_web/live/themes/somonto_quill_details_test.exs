defmodule TymeslotWeb.Live.Themes.SomontoQuillDetailsTest do
  @moduledoc """
  Somonto fork, Quill (`"1"`): the details step in three pages (your details,
  contact, summary), the meeting type's questions asked there beside the
  attendee; no "Duration" step for a page with one meeting type; the company
  and phone a booking link carries; the step names the embed reports.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :bookings
  @moduletag :themes
  @moduletag :integration

  import Mox
  import Tymeslot.JourneyFixtureHelpers

  alias Tymeslot.CalendarMock
  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.TestMocks
  alias TymeslotWeb.BookingDriver

  @theme_id "1"

  @company %{
    "id" => "cf-company",
    "type" => "short_text",
    "label" => "Name des Unternehmens",
    "required" => true,
    "position" => 0
  }

  @phone %{
    "id" => "cf-phone",
    "type" => "phone",
    "label" => "Telefonnummer",
    "required" => true,
    "position" => 1
  }

  @name_input "#booking-form input[name='booking[name]']"
  @email_input "#booking-form input[name='booking[email]']"

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    RateLimiter.clear_all()
    AvailabilityCache.clear_all()
    TestMocks.setup_all_mocks()

    old_cfg = Application.get_env(:tymeslot, :recaptcha, [])
    Application.put_env(:tymeslot, :recaptcha, Keyword.put(old_cfg, :booking_enabled, false))
    on_exit(fn -> Application.put_env(:tymeslot, :recaptcha, old_cfg) end)

    CalendarMock
    |> stub(:get_events_for_range_fresh, fn _user_id, _start, _end -> {:ok, []} end)
    |> stub(:get_booking_integration_info, fn _user_id -> {:error, :no_integration} end)

    :ok
  end

  defp one_type(username) do
    seed_organiser(@theme_id, username,
      types: [[name: "Erstgespräch", duration_minutes: 15, custom_fields: [@company, @phone]]]
    )
  end

  defp pick_ahead(view) do
    day = Date.utc_today() |> Date.add(3) |> Date.to_iso8601()
    {^day, _time} = BookingDriver.pick_first_slot(view, on: day)
  end

  defp to_details(view) do
    pick_ahead(view)
    view |> element("[data-testid='next-step']") |> render_click()
    await(view, "[data-details-page='1']")
  end

  defp next(view), do: view |> element("[data-testid='details-next']") |> render_click()
  defp back(view), do: view |> element("[data-testid='back-step']") |> render_click()

  defp page(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute("[data-details-page]", "data-details-page")
    |> List.first()
  end

  defp input_value(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute(selector, "value")
    |> List.first()
  end

  defp hidden?(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.attribute("hidden") != []
  end

  defp step_labels(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(".step-label")
    |> Enum.map(&String.trim(Floki.text(&1)))
  end

  defp step_attr(view) do
    doc = view |> render() |> Floki.parse_document!()

    {List.first(Floki.attribute(doc, "[data-somonto-step]", "data-somonto-step")),
     List.first(Floki.attribute(doc, "[data-somonto-step]", "data-somonto-step-index"))}
  end

  describe "one meeting type" do
    test "opens on the calendar, with photo and greeting, without the Duration step",
         %{conn: conn} do
      %{profile: profile} = one_type("somonto-one")
      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")

      assert has_element?(view, "#schedule-step")
      refute has_element?(view, "[data-testid='duration-option']")
      assert has_element?(view, "[data-testid='schedule-organizer']")
      assert step_labels(view) == ["Date & Time", "Details", "Confirmation"]
      refute has_element?(view, "#schedule-step [data-testid='back-step']")
      assert step_attr(view) == {"termin", "1"}
    end
  end

  describe "two meeting types" do
    test "start on the list, with the Duration step", %{conn: conn} do
      %{profile: profile} =
        seed_organiser(@theme_id, "somonto-two",
          types: [
            [name: "Erstgespräch", duration_minutes: 15, custom_fields: [@company, @phone]],
            [name: "Beratung", duration_minutes: 45, custom_fields: [@company, @phone]]
          ]
        )

      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")

      assert length(BookingDriver.meeting_types(view)) == 2
      assert step_labels(view) == ["Duration", "Date & Time", "Details", "Confirmation"]
      assert step_attr(view) == {"dauer", "1"}

      BookingDriver.choose_meeting_type(view, hd(BookingDriver.meeting_types(view)))
      await(view, "#schedule-step")
      assert step_attr(view) == {"termin", "2"}
      assert to_details(view)
      assert step_attr(view) == {"angaben", "3"}
    end
  end

  describe "the details step" do
    @tag :capture_log
    test "asks in three pages, checks each page, keeps values on Back, books", %{conn: conn} do
      %{user: user, profile: profile} = one_type("somonto-flow")
      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")
      to_details(view)

      # Page 1: company and name; email and phone hidden; no message field.
      assert page(view) == "1"
      assert step_attr(view) == {"angaben", "2"}
      refute hidden?(view, "[data-question='cf-company']")
      refute hidden?(view, ".booking-field--name")
      assert hidden?(view, ".booking-field--email")
      assert hidden?(view, ".booking-page--contact")
      refute has_element?(view, "#booking-form textarea[name='booking[message]']")
      # Every required field shows the asterisk, the company question too.
      assert has_element?(
               view,
               "[data-question='cf-company'] [data-testid='booking-question-required']"
             )

      # Next with nothing typed stays, with the errors shown.
      next(view)
      assert page(view) == "1"
      assert has_element?(view, "[data-question='cf-company'] .form-field__error")

      BookingDriver.answer(view, "cf-company", "Tischlerei Muster GmbH")
      BookingDriver.fill_attendee(view, %{name: "Max Muster"})
      next(view)
      assert page(view) == "2"
      assert step_attr(view) == {"kontakt", "3"}
      assert hidden?(view, ".booking-field--name")
      refute hidden?(view, ".booking-field--email")

      assert has_element?(
               view,
               "[data-question='cf-phone'] [data-testid='booking-question-required']"
             )

      # Back keeps what was typed.
      back(view)
      assert page(view) == "1"
      assert input_value(view, @name_input) == "Max Muster"
      assert input_value(view, "#cq-input-cf-company") == "Tischlerei Muster GmbH"
      next(view)
      assert page(view) == "2"

      # Page 2: a bad phone number stays.
      BookingDriver.fill_attendee(view, %{name: "Max Muster", email: "max@muster.at"})
      BookingDriver.answer(view, "cf-phone", "x")
      next(view)
      assert page(view) == "2"

      BookingDriver.answer(view, "cf-phone", "+43 660 1234567")
      next(view)
      assert page(view) == "3"
      assert step_attr(view) == {"uebersicht", "4"}

      summary = view |> element("[data-testid='booking-summary']") |> render()
      assert summary =~ "max@muster.at"
      assert has_element?(view, "[data-testid='booking-summary-zone']")
      assert has_element?(view, "[data-testid='submit-booking']")

      BookingDriver.submit(view, %{})
      await(view, "[data-testid='confirmation-heading']")
      assert step_attr(view) == {"bestaetigung", "5"}

      meeting =
        Repo.get_by!(MeetingSchema, organizer_user_id: user.id, attendee_email: "max@muster.at")

      assert meeting.attendee_name == "Max Muster"
      assert meeting.custom_field_answers["cf-company"] == "Tischlerei Muster GmbH"
      assert meeting.custom_field_answers["cf-phone"] =~ "660"
    end

    test "Enter in the name field moves on instead of submitting", %{conn: conn} do
      %{profile: profile} = one_type("somonto-enter")
      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")
      to_details(view)

      BookingDriver.answer(view, "cf-company", "Muster KG")
      BookingDriver.submit(view, %{name: "Eva Muster"})

      assert page(view) == "2"
      refute has_element?(view, "[data-testid='confirmation-heading']")
    end

    test "Back on the first page returns to the calendar", %{conn: conn} do
      %{profile: profile} = one_type("somonto-back")
      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")
      to_details(view)

      back(view)
      await(view, "#schedule-step")
    end
  end

  describe "prefill from the link" do
    test "fills name, company, email and phone", %{conn: conn} do
      %{profile: profile} = one_type("somonto-prefill")

      {:ok, view, _html} =
        conn
        |> put_connect_params(%{
          "attendee_prefill" => %{
            "name" => "Ada Muster",
            "email" => "ada@muster.at",
            "company" => "Muster & Söhne OG",
            "phone" => "+43 1 2345678"
          }
        })
        |> live(~p"/#{profile.username}")

      to_details(view)

      assert input_value(view, @name_input) == "Ada Muster"
      assert input_value(view, @email_input) == "ada@muster.at"
      assert input_value(view, "#cq-input-cf-company") == "Muster & Söhne OG"
      assert input_value(view, "#cq-input-cf-phone") == "+43 1 2345678"

      next(view)
      next(view)
      assert page(view) == "3"
    end

    test "drops a phone number that is none", %{conn: conn} do
      %{profile: profile} = one_type("somonto-prefill-bad")

      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"attendee_prefill" => %{"phone" => "<script>"}})
        |> live(~p"/#{profile.username}")

      to_details(view)
      assert input_value(view, "#cq-input-cf-phone") in [nil, ""]
    end
  end

  describe "the date" do
    test "never breaks between day and month (German)" do
      Gettext.put_locale(TymeslotWeb.Gettext, "de")
      on_exit(fn -> Gettext.put_locale(TymeslotWeb.Gettext, "en") end)

      assert TymeslotWeb.Themes.Shared.LocalizationHelpers.format_booking_date_time(
               "2026-11-28",
               "09:00",
               "Europe/Vienna"
             ) == "Samstag, 28.\u00a0November 2026 um 09:00"
    end
  end

  describe "the footer" do
    test "links the source code (AGPL)", %{conn: conn} do
      %{profile: profile} = one_type("somonto-agpl")
      {:ok, view, _html} = live(conn, ~p"/#{profile.username}")

      assert has_element?(
               view,
               "[data-testid='source-code-link'][href='https://github.com/somonto/tymeslot']"
             )
    end
  end
end
