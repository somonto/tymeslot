defmodule TymeslotWeb.Themes.Quill.Scheduling.Components.BookingComponent do
  @moduledoc """
  Quill theme component for the details step.

  Somonto fork: the step asks the meeting type's questions beside the
  attendee (the Quill journey's `:booking` moment collects both) over three
  short pages, kept in this component (`:details_page`):

    1. "Your details": every question that is not a phone number (the
       company name), then the attendee's name;
    2. "Contact": the email address, then the phone questions;
    3. "Summary": with whom, when (the visitor's timezone by name) and the
       address the confirmation goes to, with the submit, "Book the call".

  Every field stays in the page while another page is shown (`hidden`), so
  the one booking form submits name and email from the summary, and Back
  keeps every value typed. Next checks the fields of its own page before it
  moves on; an error then shows under its field for as long as it holds.
  Enter in a field moves on as Next does; only the summary submits. The
  booking form carries no message field. A submit the server refuses with
  an error sends the visitor back to the page holding the field.

  Each page's heading takes the focus when the page appears, and the page
  root names the screen for the embed (`data-somonto-step`, read by
  `iframe_embed.js`, which reports it to the embedding page as
  `tymeslot-step`).
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.CustomFields
  alias Tymeslot.Meetings.Approval
  alias Tymeslot.Security.InputProcessor
  alias TymeslotWeb.Live.Scheduling.BookingConfig
  alias TymeslotWeb.Live.Scheduling.OrganizerHelpers
  alias TymeslotWeb.Themes.Shared.BookingLabels
  alias TymeslotWeb.Themes.Quill.Scheduling.Components.MeetingSummary
  alias TymeslotWeb.Themes.Shared.BookingLocation
  alias TymeslotWeb.Themes.Shared.BookingText
  alias TymeslotWeb.Themes.Shared.Components.ApprovalNotice
  alias TymeslotWeb.Themes.Shared.Components.BookingForm
  alias TymeslotWeb.Themes.Shared.Components.GuestField
  alias TymeslotWeb.Themes.Shared.Components.LocationField
  alias TymeslotWeb.Themes.Shared.Components.MeetingPrice
  alias TymeslotWeb.Themes.Shared.Components.SubmitPrice
  alias TymeslotWeb.Themes.Shared.CustomQuestions.Engine
  alias TymeslotWeb.Themes.Shared.CustomQuestions.Events
  alias TymeslotWeb.Themes.Shared.CustomQuestions.Inputs.Renderer, as: InputRenderer
  alias TymeslotWeb.Themes.Shared.GuestBooking
  alias TymeslotWeb.Themes.Shared.Journey.Runtime
  alias TymeslotWeb.Themes.Shared.LocalizationHelpers
  alias TymeslotWeb.Themes.Shared.SomontoSteps
  alias TymeslotWeb.Themes.Shared.StepEvents

  use TymeslotWeb.Components.CoreComponents

  @question_events ~w(answer multi_toggle)
  @form_fields ~w(name email)
  @page_steps %{1 => "angaben", 2 => "kontakt", 3 => "uebersicht"}

  @impl Phoenix.LiveComponent
  def update(%{details_next: true}, socket), do: {:ok, next_page(socket, nil)}

  def update(assigns, socket) do
    {:ok, socket} = StepEvents.update(assigns, socket)

    socket =
      socket
      |> assign_new(:details_page, fn -> 1 end)
      |> assign_new(:attempted, fn -> MapSet.new() end)
      |> back_to_refused_field()

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event(event, params, socket) when event in @question_events,
    do: Events.handle_event(event, params, socket)

  # Somonto: answers and form changes reach this component through the
  # LiveView (`send(self(), ...)`). A click that arrives together with the
  # last field's blur would be checked against the values before it, and the
  # first Next would do nothing. Queued behind them, it sees what was typed.
  def handle_event("details_next", _params, socket), do: queue_next(socket)

  # Enter in a question's own form: the same as Next on its page.
  def handle_event("next_step", _params, socket), do: queue_next(socket)

  def handle_event("details_back", _params, socket), do: previous_page(socket)
  def handle_event("back_step", _params, socket), do: previous_page(socket)

  # Enter in the name or email field submits the booking form: before the
  # summary that moves on as Next does, with the values just typed.
  def handle_event(
        "submit",
        %{"booking" => booking_params},
        %{assigns: %{details_page: page}} = socket
      )
      when page < 3 do
    send(self(), {:step_event, StepEvents.moment(socket.assigns), :validate, booking_params})
    {:noreply, next_page(socket, booking_params)}
  end

  def handle_event(event, params, socket), do: StepEvents.handle_event(event, params, socket)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    questions = questions_with_errors(assigns)
    page = assigns.details_page

    assigns =
      assign(assigns,
        navigable_steps: Runtime.navigable_steps(assigns),
        step_numbers: Runtime.step_numbers(assigns),
        next_day_end: LocalizationHelpers.booking_next_day_end(assigns),
        organizer_name: get_organizer_name(assigns.organizer_profile, assigns.username_context),
        page: page,
        step_name: Map.fetch!(@page_steps, page),
        step_index: SomontoSteps.index(assigns, :booking) + page - 1,
        first_questions: Enum.reject(questions, &phone_question?(&1.definition)),
        contact_questions: Enum.filter(questions, &phone_question?(&1.definition)),
        form_errors: form_errors(assigns),
        summary_snapshot: summary_snapshot(questions),
        summary_answers: summary_answers(assigns.form, questions)
      )

    ~H"""
    <div
      class="container quill-container flex-1"
      data-locale={@locale}
      id={assigns[:moment] && "#{assigns[:moment]}-step"}
      data-moment={assigns[:moment]}
      data-moment-state={assigns[:moment_state]}
      data-details-page={@page}
      data-somonto-step={@step_name}
      data-somonto-step-index={@step_index}
    >
      <.page_layout
        show_steps={true}
        navigable_steps={@navigable_steps}
        step_numbers={@step_numbers}
        current_step={3}
        hide_duration={SomontoSteps.hide_duration?(assigns)}
        slug={@duration}
        username_context={@username_context}
      >
        <div class="stack">
          <div class="flex-1 flex items-center justify-center px-4 py-4">
            <div class="w-full">
              <.glass_morphism_card class="booker-card booking-form-card" data-testid="booker-card">
                <div class="booking-card-body">
                  <h1
                    id={"booking-page-heading-#{@page}"}
                    class="section-header booking-heading booking-heading-wrapper"
                    tabindex="-1"
                    data-testid="booking-page-heading"
                    phx-mounted={JS.focus()}
                  >
                    {page_heading(@page)}
                  </h1>

                  <p
                    :if={@page != 3}
                    class="booking-datetime text-quill-secondary"
                    data-testid="booking-datetime"
                  >
                    {LocalizationHelpers.format_booking_date_time(
                      @selected_date,
                      @selected_time,
                      @user_timezone
                    )}
                    <span class="booking-datetime__zone">
                      {LocalizationHelpers.format_zone_label(
                        @selected_date,
                        @selected_time,
                        @user_timezone
                      )}
                    </span>
                  </p>

                  <div class="booking-page booking-page--details" hidden={@page != 1}>
                    <.question
                      :for={question <- @first_questions}
                      question={question}
                      target={@myself}
                    />
                  </div>

                  <BookingForm.booking_form
                    form={@form}
                    validation_errors={@form_errors}
                    target={@myself}
                    class="booking-form-fields"
                    show_message={false}
                    hidden_fields={hidden_fields(@page)}
                    labels={labels()}
                    organizer_name={@organizer_name}
                    privacy_policy_url={
                      if @page == 3, do: BookingForm.privacy_policy_url(assigns[:legal_links])
                    }
                  >
                    <div class="booking-page booking-page--contact" hidden={@page != 2}>
                      <.question
                        :for={question <- @contact_questions}
                        question={question}
                        target={@myself}
                      />

                      <LocationField.location_field
                        :if={BookingLocation.choice_required?(assigns)}
                        location_options={@location_options}
                        selected_location_id={@selected_location_id}
                        video_choices={BookingLocation.video_choices(assigns)}
                        selected_video_id={@selected_video_id}
                        venue_choices={BookingLocation.venue_choices(assigns)}
                        selected_venue_id={@selected_venue_id}
                        kept_location={BookingLocation.kept_location(assigns)}
                        location_phone={@location_phone}
                        location_error={@location_error}
                        phone_required={BookingLocation.phone_required?(assigns)}
                        target={@myself}
                      />

                      <GuestField.guest_field
                        :if={guests_allowed?(assigns)}
                        guest_emails={@guest_emails}
                        guest_input={@guest_input}
                        guest_error={@guest_error}
                        guests_open={@guests_open}
                        max_guests={@max_guests}
                        show_cap={@guest_cap_visible}
                        target={@myself}
                      />
                    </div>

                    <div
                      :if={@page == 3}
                      class="booking-page booking-page--summary"
                      data-testid="booking-summary"
                    >
                      <MeetingSummary.card
                        title={@meeting_type && @meeting_type.name}
                        date={@selected_date}
                        time={@selected_time}
                        duration={BookingText.duration_label(assigns)}
                        timezone={@user_timezone}
                        next_day_end={@next_day_end}
                        location={BookingLocation.chosen_display(assigns)}
                        video={match?(%{kind: :video}, BookingLocation.selected(assigns))}
                        arranged={BookingLocation.arranged_after_booking?(assigns)}
                        snapshot={@summary_snapshot}
                        answers={@summary_answers}
                      />

                      <MeetingPrice.hint
                        :if={!@is_rescheduling}
                        meeting_type={@meeting_type}
                        currency={@host_currency}
                        locale={@locale}
                      />

                      <ApprovalNotice.block
                        :if={Approval.required?(@meeting_type)}
                        organizer_name={@organizer_name}
                        payment_required={@meeting_type.payment_required}
                        stage={:before}
                      />

                      <SubmitPrice.price
                        meeting_type={@meeting_type}
                        currency={@host_currency}
                        locale={@locale}
                        rescheduling={@is_rescheduling}
                        class="booking-submit-price"
                      />
                    </div>
                  </BookingForm.booking_form>

                  <div class="booking-actions">
                    <.action_button
                      type="button"
                      phx-click="details_back"
                      phx-target={@myself}
                      data-testid="back-step"
                      data-intent="back"
                      variant={:secondary}
                      disabled={@submitting}
                      class="flex-1 gap-2"
                    >
                      <.icon name="hero-arrow-left" class="inline-icon" />
                      {dgettext("booking", "Back")}
                    </.action_button>

                    <.action_button
                      :if={@page < 3}
                      type="button"
                      phx-click="details_next"
                      phx-target={@myself}
                      data-testid="details-next"
                      data-intent="continue"
                      class="flex-1 gap-2"
                    >
                      {dgettext("booking", "Next")}
                      <.icon name="hero-arrow-right" class="inline-icon" />
                    </.action_button>

                    <.loading_button
                      :if={@page == 3}
                      type="submit"
                      form="booking-form"
                      id="submit-booking-button"
                      loading={@submitting}
                      loading_text={dgettext("booking", "Verifying...")}
                      disabled={!OrganizerHelpers.form_valid?(@form)}
                      data-testid="submit-booking"
                      aria-describedby={
                        SubmitPrice.describedby(
                          @meeting_type,
                          @host_currency,
                          @locale,
                          @is_rescheduling
                        )
                      }
                      data-intent="submit"
                      class="flex-1"
                      title={get_submit_title(@submitting, @form)}
                    >
                      {submit_label(@is_rescheduling, @meeting_type)}
                    </.loading_button>
                  </div>
                </div>
              </.glass_morphism_card>
            </div>
          </div>
        </div>
      </.page_layout>
    </div>
    """
  end

  # One question with its visible label and its error. The input is the
  # shared one (its own form, `answer` on change, Enter moves on).
  attr :question, :map, required: true
  attr :target, :any, required: true

  defp question(assigns) do
    ~H"""
    <div
      class={["booking-question", @question.error && "booking-question--invalid"]}
      data-testid="booking-question"
      data-question={@question.definition["id"]}
    >
      <label class="booking-question__label" for={"cq-input-#{@question.definition["id"]}"}>
        {@question.definition["label"]}
        <%!-- Somonto fork: the asterisk Name and Email carry, on a required
             question too. The input states the requirement itself. --%>
        <span
          :if={@question.definition["required"] == true}
          class="text-red-500 ml-0.5"
          aria-hidden="true"
          data-testid="booking-question-required"
        >*</span>
      </label>
      <p :if={@question.definition["help_text"]} class="booking-question__help">
        {@question.definition["help_text"]}
      </p>
      <InputRenderer.render
        definition={@question.definition}
        value={@question.value}
        myself={@target}
        autofocus={false}
        theme_key={:quill}
      />
      <p :if={@question.error} class="form-field__error" role="alert">{@question.error}</p>
    </div>
    """
  end

  # ========== Pages ==========

  defp page_heading(1), do: dgettext("booking", "Your details")
  defp page_heading(2), do: dgettext("booking", "Contact")
  defp page_heading(3), do: dgettext("booking", "Summary")

  # Name on the first page, email on the second, both hidden on the summary.
  defp hidden_fields(1), do: [:email]
  defp hidden_fields(2), do: [:name]
  defp hidden_fields(_summary), do: [:name, :email]

  defp labels do
    Map.merge(BookingForm.default_labels(), %{
      name: dgettext("booking", "Your Name"),
      name_placeholder: "",
      email: dgettext("booking", "Email"),
      email_placeholder: ""
    })
  end

  defp queue_next(socket) do
    send_update(self(), __MODULE__, id: socket.assigns.id, details_next: true)
    {:noreply, socket}
  end

  defp next_page(socket, submitted_params) do
    page = socket.assigns.details_page
    fields = page_fields(socket.assigns, page)
    attempted = Enum.reduce(fields, socket.assigns.attempted, &MapSet.put(&2, &1))
    socket = assign(socket, :attempted, attempted)

    if page < 3 and page_valid?(socket.assigns, fields, submitted_params),
      do: assign(socket, :details_page, page + 1),
      else: socket
  end

  defp previous_page(%{assigns: %{details_page: page}} = socket) when page > 1,
    do: {:noreply, assign(socket, :details_page, page - 1)}

  defp previous_page(socket), do: StepEvents.handle_event("back_step", %{}, socket)

  # The fields a page checks: the form's ("name", "email") and the ids of
  # its questions.
  defp page_fields(assigns, 1),
    do: question_ids(assigns, &(not phone_question?(&1))) ++ ["name"]

  defp page_fields(assigns, 2), do: ["email" | question_ids(assigns, &phone_question?/1)]
  defp page_fields(_assigns, _page), do: []

  defp question_ids(%{engine: %Engine{definitions: definitions}}, keep?),
    do: for(definition <- definitions, keep?.(definition), do: definition["id"])

  defp question_ids(_assigns, _keep?), do: []

  defp page_valid?(assigns, fields, submitted_params) do
    form_errors = processor_errors(submitted_params || form_values(assigns.form))

    Enum.all?(fields, fn
      field when field in @form_fields ->
        not Map.has_key?(form_errors, String.to_existing_atom(field))

      id ->
        question_error(assigns, id) == nil
    end)
  end

  # After a refused submit, the first page holding a field in error.
  defp back_to_refused_field(%{assigns: %{details_page: 3} = assigns} = socket) do
    errors = assigns[:validation_errors] || %{}
    refused = assigns[:refused_questions] || MapSet.new()

    target =
      Enum.find([1, 2], fn page ->
        Enum.any?(page_fields(assigns, page), fn
          field when field in @form_fields ->
            Map.has_key?(errors, String.to_existing_atom(field))

          id ->
            MapSet.member?(refused, id)
        end)
      end)

    if target, do: assign(socket, :details_page, target), else: socket
  end

  defp back_to_refused_field(socket), do: socket

  # ========== Errors ==========

  # The form's own errors (shown once a field was blurred), and for a field
  # Next has checked, its error as of now.
  defp form_errors(assigns) do
    attempted =
      for field <- @form_fields,
          MapSet.member?(assigns.attempted, field),
          do: String.to_existing_atom(field)

    assigns.form
    |> form_values()
    |> processor_errors()
    |> Map.take(attempted)
    |> Map.merge(assigns[:validation_errors] || %{})
  end

  defp processor_errors(params) when is_map(params) do
    case InputProcessor.validate_form(params, BookingConfig.booking_field_spec()) do
      {:error, %{} = errors} -> errors
      _valid_or_unreadable -> %{}
    end
  end

  defp processor_errors(_params), do: %{}

  # Every question with its error: the shared rule (touched or refused) or a
  # question Next has checked.
  defp questions_with_errors(assigns) do
    attempted = assigns[:attempted] || MapSet.new()

    assigns
    |> Events.all_questions()
    |> Enum.map(fn question ->
      id = question.definition["id"]

      if question.error == nil and MapSet.member?(attempted, id),
        do: %{question | error: question_error(assigns, id)},
        else: question
    end)
  end

  defp question_error(%{engine: %Engine{} = engine}, id) do
    with %{} = definition <- Enum.find(engine.definitions, &(&1["id"] == id)),
         {:error, message} <-
           CustomFields.validate_answer(Map.get(engine.answers, id), definition) do
      message
    else
      _valid_or_unknown -> nil
    end
  end

  defp question_error(_assigns, _id), do: nil

  # A phone number goes with the email on the contact page.
  # The summary's "Your details": name and email address first, then the
  # meeting type's questions, each as the guest typed it.
  @summary_name "somonto-name"
  @summary_email "somonto-email"

  defp summary_snapshot(questions) do
    [
      %{"id" => @summary_name, "type" => "short_text", "label" => dgettext("booking", "Name")},
      %{"id" => @summary_email, "type" => "email", "label" => dgettext("booking", "Email address")}
      | Enum.map(questions, & &1.definition)
    ]
  end

  defp summary_answers(form, questions) do
    Map.new(questions, &{&1.definition["id"], trim(&1.value)})
    |> Map.put(@summary_name, form_value(form, "name"))
    |> Map.put(@summary_email, form_value(form, "email"))
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp phone_question?(%{"type" => "phone"}), do: true

  defp phone_question?(%{"label" => label}) when is_binary(label),
    do: label |> String.trim() |> String.downcase() |> String.starts_with?("telefon")

  defp phone_question?(_definition), do: false

  defp form_values(%Phoenix.HTML.Form{params: params})
       when is_map(params) and map_size(params) > 0,
       do: params

  defp form_values(%Phoenix.HTML.Form{source: %{} = source}), do: source
  defp form_values(_form), do: %{}

  defp form_value(form, key) do
    case form_values(form) do
      %{^key => value} when is_binary(value) -> String.trim(value)
      _none -> ""
    end
  end

  # ========== Labels ==========

  # "Book" is a promise the button cannot keep on a gated meeting type, where
  # pressing it sends a request; the shared labels name that case and a
  # reschedule.
  defp submit_label(is_rescheduling, meeting_type) do
    BookingLabels.submit_label(
      is_rescheduling,
      meeting_type,
      dgettext("booking", "Book the call"),
      :quill
    )
  end

  defp guests_allowed?(assigns), do: GuestBooking.guests_allowed?(assigns)

  defp get_organizer_name(organizer_profile, username_context) do
    BookingLabels.organizer_display_name(organizer_profile, username_context)
  end

  defp get_submit_title(submitting, form) do
    cond do
      submitting ->
        dgettext("booking", "Verifying slot availability and creating your meeting...")

      !OrganizerHelpers.form_valid?(form) ->
        dgettext("booking", "Please fill in all required fields")

      true ->
        dgettext("booking", "Click to schedule your meeting")
    end
  end
end
