defmodule TymeslotWeb.Themes.Quill.Scheduling.Components.MeetingSummary do
  @moduledoc """
  Somonto fork: the meeting card, shown once, on the summary page before the
  guest books (the card Quill showed on its confirmation step until then).

  The meeting type as its heading, date, time, duration and zone as a grid,
  the location with, for a video call, how to join; below it the guest's own
  details (name, email address and the meeting type's questions) as label
  and value. The confirmation step after booking no longer repeats it.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Themes.Shared.Components.CustomAnswers
  alias TymeslotWeb.Themes.Shared.Components.LocationField
  alias TymeslotWeb.Themes.Shared.LocalizationHelpers

  attr :title, :string, default: nil, doc: "the meeting type's name"
  attr :date, :string, required: true
  attr :time, :string, required: true
  attr :duration, :string, required: true, doc: "the formatted duration"
  attr :timezone, :string, required: true
  attr :next_day_end, :string, default: nil, doc: "when the meeting ends on a later day"
  attr :location, :string, default: nil, doc: "the chosen location, as the guest reads it"
  attr :video, :boolean, default: false, doc: "whether the location is a video call"
  attr :arranged, :boolean, default: false, doc: "an in-person address arranged later"
  attr :snapshot, :list, default: [], doc: "the guest's details as questions"
  attr :answers, :map, default: %{}, doc: "their values, keyed by question id"

  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    ~H"""
    <div class="meeting-details-card" data-testid="meeting-summary">
      <h2
        :if={@title not in [nil, ""]}
        class="meeting-details-title"
        data-testid="chosen-meeting-type"
      >
        {@title}
      </h2>
      <.booking_details
        date={@date}
        time={@time}
        duration={@duration}
        timezone={@timezone}
        next_day_end={@next_day_end}
      />

      <div :if={@location} class="confirmation-border-top mt-3 pt-3 border-t">
        <div class="confirmation-email-row" data-testid="confirmation-location">
          <div class="confirmation-icon-wrapper rounded-full">
            <Icons.icon name="hero-map-pin" class="confirmation-email-link w-4 h-4" />
          </div>
          <p class="text-sm text-white">
            {dgettext("booking", "Location")}:
            <span class="confirmation-email-link font-semibold">{@location}</span>
          </p>
        </div>
        <p :if={@video} class="location-field__note" data-testid="video-note">
          {dgettext("booking", "In the browser, on a phone or computer. You don't need a camera.")}
        </p>
        <LocationField.arranged_note :if={@arranged} />
      </div>
    </div>

    <CustomAnswers.custom_answers
      snapshot={@snapshot}
      answers={@answers}
      heading={dgettext("booking", "Your details")}
    />
    """
  end

  attr :date, :string, required: true
  attr :time, :string, required: true
  attr :duration, :string, required: true
  attr :timezone, :string, required: true
  attr :next_day_end, :string, default: nil

  defp booking_details(assigns) do
    assigns =
      assign(assigns,
        formatted_date: LocalizationHelpers.format_date(assigns.date),
        formatted_time: LocalizationHelpers.format_slot_label(assigns.time),
        formatted_timezone:
          LocalizationHelpers.format_zone_label(assigns.date, assigns.time, assigns.timezone)
      )

    ~H"""
    <div class="booking-details-grid">
      <div>
        <p class="booking-detail-label">{dgettext("booking", "Date")}</p>
        <p class="booking-detail-value">{@formatted_date}</p>
      </div>
      <div>
        <p class="booking-detail-label">{dgettext("booking", "Time")}</p>
        <p class="booking-detail-value">{@formatted_time}</p>
        <p :if={@next_day_end} class="booking-detail-value" data-testid="booking-next-day-end">
          {@next_day_end}
        </p>
      </div>
      <div>
        <p class="booking-detail-label">{dgettext("booking", "Duration")}</p>
        <p class="booking-detail-value">{@duration}</p>
      </div>
      <div>
        <p class="booking-detail-label">{dgettext("booking", "Timezone")}</p>
        <p class="booking-detail-value">{@formatted_timezone}</p>
      </div>
    </div>
    """
  end
end
