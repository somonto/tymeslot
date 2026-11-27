defmodule TymeslotWeb.Themes.Quill.Scheduling.Live do
  @moduledoc """
  Quill theme scheduling LiveView: the shared booking flow in Quill's
  glassmorphism wrapper and step components.

  Somonto fork: the meeting type's questions are asked inside the details
  step (`BookingComponent`), which collects the answers beside the attendee
  over three short pages (your details, contact, summary), instead of one
  question per page in a step of their own. The journey is otherwise the
  classic one, on the route the visit arrived on (`url: :route`).
  """

  alias TymeslotWeb.Themes.Quill.Scheduling.Components.{
    BookingComponent,
    ConfirmationComponent,
    LengthComponent,
    OverviewComponent,
    ScheduleComponent
  }

  alias TymeslotWeb.Themes.Quill.Scheduling.Wrapper
  alias TymeslotWeb.Themes.Shared.Journey.Navigators.Paged

  use TymeslotWeb.Themes.Shared.SchedulingLive,
    wrapper: &Wrapper.quill_wrapper/1,
    journey: [
      navigator: Paged,
      moments: [
        {:overview, collects: [:meeting_type], component: OverviewComponent},
        {:length, collects: [:length], component: LengthComponent},
        {:schedule, collects: [:slot], component: ScheduleComponent},
        {:booking, collects: [:answers, :attendee], component: BookingComponent}
      ],
      outcomes: %{confirmation: ConfirmationComponent, awaiting_payment: :shared},
      url: :route
    ]
end
