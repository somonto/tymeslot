defmodule TymeslotWeb.Themes.Shared.SomontoSteps do
  @moduledoc """
  Somonto fork: what the Quill booking page shows of its steps.

    * `maybe_skip_overview/1`: a booking page offering exactly one meeting
      type opens on its calendar, not on a list of one ("Duration" has
      nothing to ask). The visitor then counts as one who came by a direct
      link (`entered_via_overview: false`), so neither Back nor the step
      indicator leads to the list.
    * `hide_duration?/1`: the step indicator leaves out "Duration" for a
      visitor who did not come through the list of meeting types and has no
      length to choose.
    * `index/2`: the number of a screen as the visitor counts them, for the
      `tymeslot-step` message to the embedding page (`iframe_embed.js`).

  Only the Quill journey is concerned; every other theme is left as it is.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.MeetingTypes
  alias TymeslotWeb.Themes.Shared.ChosenLength
  alias TymeslotWeb.Themes.Shared.Journey.Facts.MeetingType
  alias TymeslotWeb.Themes.Shared.Journey.Runtime

  @quill_live TymeslotWeb.Themes.Quill.Scheduling.Live

  @doc """
  On the Quill journey's overview with exactly one meeting type (and no
  reschedule): selects it and moves on to the next moment, without taking
  the focus (nothing was pressed). Any other page is returned unchanged.
  """
  @spec maybe_skip_overview(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_skip_overview(%{assigns: assigns} = socket) do
    with true <- quill?(assigns),
         :overview <- assigns[:current_state],
         [only] <- assigns[:meeting_types] || [],
         false <- rescheduling?(assigns) do
      {:noreply, socket} =
        MeetingType.handle(socket, :select_duration, MeetingTypes.effective_slug(only))

      socket = assign(socket, :entered_via_overview, false)

      case Runtime.handle_step_event(socket, :overview, :next_step, nil) do
        {:noreply, moved} -> assign(moved, :journey_focus, nil)
        _unhandled -> socket
      end
    else
      _not_concerned -> socket
    end
  end

  @doc "Whether the step indicator leaves out the \"Duration\" step."
  @spec hide_duration?(map()) :: boolean()
  def hide_duration?(assigns),
    do: assigns[:entered_via_overview] != true and not ChosenLength.choose?(assigns)

  @doc """
  The screen's number as the visitor counts them, from 1: the journey's
  number of `moment`, one less when the list of meeting types was passed
  over. The details step adds its page to it; the confirmation is the one
  after the details' summary.
  """
  @spec index(map(), atom()) :: pos_integer()
  def index(assigns, moment) do
    numbers = Runtime.step_numbers(assigns)
    number = Map.get(numbers, moment) || map_size(numbers) + 1
    skipped = if Map.has_key?(numbers, :overview) and hide_duration?(assigns), do: 1, else: 0
    max(number - skipped, 1)
  end

  defp quill?(%{journey: journey}) when not is_nil(journey),
    do: Code.ensure_loaded?(@quill_live) and journey == @quill_live.__journey__()

  defp quill?(_assigns), do: false

  defp rescheduling?(assigns),
    do:
      assigns[:is_rescheduling] == true or is_binary(assigns[:reschedule_meeting_uid]) or
        is_binary(assigns[:reschedule_seat_token])
end
