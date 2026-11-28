defmodule TymeslotWeb.Themes.Quill.Scheduling.Components.ConfirmationComponent do
  @moduledoc """
  Quill theme component for the confirmation/thank you step.
  Features glassmorphism design with elegant transparency effects.

  Somonto fork: short. A tick, "Meeting booked", where the invitation went,
  then adding to the calendar, booking another and how to reschedule. The
  meeting's details and the guest's answers were on the summary page just
  before (`MeetingSummary`), so they are not repeated here.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Profiles
  alias TymeslotWeb.Themes.Shared.ApprovalDisplay
  alias TymeslotWeb.Themes.Shared.Components.ApprovalNotice
  alias TymeslotWeb.Themes.Shared.Components.GroupSession
  alias TymeslotWeb.Themes.Shared.ConfirmationText
  alias TymeslotWeb.Themes.Shared.Journey.Runtime
  alias TymeslotWeb.Themes.Shared.PathHandlers
  alias TymeslotWeb.Themes.Shared.SomontoSteps
  alias TymeslotWeb.Themes.Shared.StepEvents

  use TymeslotWeb.Components.CoreComponents

  @impl Phoenix.LiveComponent
  defdelegate update(assigns, socket), to: StepEvents

  @impl Phoenix.LiveComponent
  defdelegate handle_event(event, params, socket), to: StepEvents

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assign(assigns,
        navigable_steps: Runtime.navigable_steps(assigns),
        step_numbers: Runtime.step_numbers(assigns)
      )

    ~H"""
    <div
      class="container quill-container flex-1"
      data-locale={@locale}
      data-somonto-step="bestaetigung"
      data-somonto-step-index={SomontoSteps.index(assigns, :booking) + 3}
    >
      <.page_layout
        show_steps={true}
        navigable_steps={@navigable_steps}
        step_numbers={@step_numbers}
        hide_duration={SomontoSteps.hide_duration?(assigns)}
        current_step={4}
        slug={@duration}
        username_context={@username_context}
      >
        <div class="stack">
          <div class="confirmation-outer flex-1 flex items-center justify-center">
            <div class="w-full confirmation-container">
              <.glass_morphism_card class="booker-card" data-testid="booker-card">
                <div class="confirmation-content">
                  <div class="confirmation-heading-row flex items-center">
                    <div class="shrink-0">
                      <div class="relative">
                        <div class={[
                          "confirmation-badge rounded-full flex items-center justify-center",
                          ApprovalDisplay.awaiting_approval?(assigns) && "confirmation-badge--pending"
                        ]}>
                          <.icon
                            :if={!ApprovalDisplay.awaiting_approval?(assigns)}
                            name="hero-check"
                            class="confirmation-badge-icon stroke-3"
                          />
                          <.icon
                            :if={ApprovalDisplay.awaiting_approval?(assigns)}
                            name="hero-clock"
                            class="confirmation-badge-icon stroke-3"
                          />
                        </div>
                      </div>
                    </div>
                    <div class="flex-1 min-w-0" data-testid="confirmation-heading">
                      <h1 class="section-header confirmation-title">
                        {headline(assigns)}
                      </h1>
                      <p class="confirmation-subtitle text-quill-primary">
                        {subtitle(assigns)}
                      </p>
                    </div>
                  </div>

                  <ApprovalNotice.block
                    :if={ApprovalDisplay.awaiting_approval?(assigns)}
                    organizer_name={Profiles.display_name(@organizer_profile)}
                    stage={:after}
                    class="mt-4"
                  />

                  <GroupSession.confirmation_line meeting_type={@meeting_type} class="mt-4" />

                  <div class="confirmation-actions">
                    <a
                      :if={PathHandlers.calendar_ics_path(assigns)}
                      href={PathHandlers.calendar_ics_path(assigns)}
                      download
                      class="action-button action-button--primary calendar-download-button"
                      data-testid="add-to-calendar"
                    >
                      <.icon name="hero-calendar-days" class="calendar-download-icon" />
                      {if ApprovalDisplay.awaiting_approval?(assigns),
                        do: dgettext("booking", "Add tentative hold to calendar"),
                        else: dgettext("booking", "Add to calendar")}
                    </a>
                    <button
                      type="button"
                      phx-click="schedule_another"
                      phx-target={@myself}
                      data-testid="schedule-another"
                      data-intent="restart"
                      class="confirmation-restart-link"
                    >
                      {dgettext("booking", "Schedule Another Meeting")}
                    </button>
                  </div>

                  <p class="confirmation-help-text mt-3 text-xs">
                    {if ApprovalDisplay.awaiting_approval?(assigns),
                      do:
                        dgettext(
                          "booking",
                          "Changed your mind? Your request email has a link to withdraw it."
                        ),
                      else: dgettext("booking", "Need to reschedule? Check your confirmation email.")}
                  </p>
                </div>
              </.glass_morphism_card>
            </div>
          </div>
        </div>
      </.page_layout>
    </div>
    """
  end

  # ========== PRIVATE HELPERS ==========

  # A held request is not a confirmed meeting, and this screen is the last thing
  # an invitee sees before the emails arrive, so the heading changes too, not
  # just a note underneath it. Which status applies is decided in
  # ConfirmationText; only the wording is Quill's.
  defp headline(assigns) do
    case ConfirmationText.status(assigns) do
      :held -> dgettext("booking", "Request sent!")
      :rescheduled -> dgettext("booking", "Meeting Rescheduled!")
      # Somonto fork: German "Termin gebucht" (catalogue), the details were on the summary.
      :confirmed -> dgettext("booking", "Meeting Confirmed!")
    end
  end

  defp subtitle(assigns) do
    case ConfirmationText.status(assigns) do
      :held ->
        ConfirmationText.held_message(assigns[:name], assigns[:organizer_profile], :quill)

      :rescheduled ->
        dgettext("booking", "%{name}, your meeting %{organizer} has been rescheduled.",
          name: assigns[:name],
          organizer: ConfirmationText.organizer_fragment(assigns[:organizer_profile], :quill)
        )

      # Somonto fork: where the invitation went, instead of the name twice. The
      # address sits in its own inline block, so a narrow screen moves it to the
      # next line whole instead of breaking it at a hyphen.
      :confirmed ->
        marker = "\u{E000}"

        [before | rest] =
          dgettext("booking", "We have sent you the meeting invitation by email to %{email}.",
            email: marker
          )
          |> String.split(marker, parts: 2)

        assigns = assign(assigns, before: before, after: Enum.join(rest), address: assigns[:email])

        ~H|{@before}<span class="confirmation-email" data-testid="confirmation-email">{@address}</span>{@after}|
    end
  end
end
