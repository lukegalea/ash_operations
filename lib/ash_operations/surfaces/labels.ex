defmodule AshOperations.Surfaces.Labels do
  @moduledoc """
  The labels of the operator surfaces, one function per phrase, looked up in the
  `ash_operations_surfaces` gettext domain of `AshOperations.Gettext`.

  A surface macro calls `text/1` while it expands, so the label is the msgid (or its translation
  for the compile-time locale) and ash_a2ui's own metadata extraction picks it up for runtime
  translation.
  """
  use Gettext, backend: AshOperations.Gettext

  @domain "ash_operations_surfaces"

  @type key ::
          :deliveries_title
          | :deliveries_empty_title
          | :deliveries_empty_message
          | :provider
          | :endpoint
          | :dedup_key
          | :event_type
          | :subject_id
          | :signature_verdict
          | :state
          | :received_at
          | :followed_up_at
          | :reconcile_now
          | :reconcile_prompt_title

  @doc "The label for `key`."
  @spec text(key()) :: String.t()
  def text(:deliveries_title), do: dgettext(@domain, "Webhook deliveries")
  def text(:delivery_record), do: dgettext(@domain, "delivery")
  def text(:deliveries_empty_title), do: dgettext(@domain, "No deliveries")

  def text(:deliveries_empty_message),
    do: dgettext(@domain, "Deliveries the providers send appear here.")

  def text(:provider), do: dgettext(@domain, "Provider")
  def text(:endpoint), do: dgettext(@domain, "Endpoint")
  def text(:dedup_key), do: dgettext(@domain, "Delivery id")
  def text(:event_type), do: dgettext(@domain, "Event type")
  def text(:subject_id), do: dgettext(@domain, "Subject")
  def text(:signature_verdict), do: dgettext(@domain, "Signature")
  def text(:state), do: dgettext(@domain, "Follow-up")
  def text(:received_at), do: dgettext(@domain, "Received")
  def text(:followed_up_at), do: dgettext(@domain, "Followed up")
  def text(:reconcile_now), do: dgettext(@domain, "Reconcile now")
  def text(:reconcile_prompt_title), do: dgettext(@domain, "Why reconcile this delivery now?")
end
