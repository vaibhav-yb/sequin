defmodule Sequin.ConsumerEventTest do
  use Sequin.DataCase, async: true

  alias Sequin.Consumers
  alias Sequin.Consumers.ConsumerEvent
  alias Sequin.Factory
  alias Sequin.Factory.ConsumersFactory

  describe "ConsumerEvent" do
    setup do
      consumer = ConsumersFactory.insert_consumer!(message_kind: :event)
      %{consumer: consumer}
    end

    test "insert_consumer_events/2 inserts batch of consumer events", %{consumer: consumer} do
      events =
        for _ <- 1..3 do
          %{consumer_id: consumer.id}
          |> ConsumersFactory.consumer_event_attrs()
          |> Map.update(:data, %{}, fn data ->
            data
            |> Sequin.Map.atomize_keys()
            |> Map.update!(:metadata, &Sequin.Map.atomize_keys/1)
          end)
        end

      assert {:ok, 3} = Consumers.insert_consumer_events(events)

      inserted_events = Repo.all(ConsumerEvent)
      assert length(inserted_events) == 3

      assert_lists_equal(inserted_events, events, fn e1, e2 ->
        e1
        |> Map.update!(:data, fn data ->
          data
          |> Map.update!(:metadata, &Map.from_struct/1)
          |> Map.from_struct()
        end)
        |> assert_maps_equal(e2, [:consumer_id, :commit_lsn, :data])
      end)
    end

    test "list_consumer_events_for_consumer/2 returns events only for the specified consumer", %{consumer: consumer} do
      other_consumer = ConsumersFactory.insert_consumer!(message_kind: :event)

      for _ <- 1..3, do: ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id)
      ConsumersFactory.insert_consumer_event!(consumer_id: other_consumer.id)

      fetched_events1 = Consumers.list_consumer_events_for_consumer(consumer.id)
      assert length(fetched_events1) == 3
      assert Enum.all?(fetched_events1, &(&1.consumer_id == consumer.id))

      fetched_events2 = Consumers.list_consumer_events_for_consumer(other_consumer.id)
      assert length(fetched_events2) == 1
      assert Enum.all?(fetched_events2, &(&1.consumer_id == other_consumer.id))
    end

    test "list_consumer_events_for_consumer/2 filters events by is_deliverable", %{consumer: consumer} do
      deliverable_events = for _ <- 1..3, do: ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id)

      ConsumersFactory.insert_consumer_event!(
        consumer_id: consumer.id,
        not_visible_until: DateTime.add(DateTime.utc_now(), 30, :second)
      )

      fetched_deliverable = Consumers.list_consumer_events_for_consumer(consumer.id, is_deliverable: true)
      assert length(fetched_deliverable) == 3
      assert_lists_equal(fetched_deliverable, deliverable_events, &(&1.id == &2.id))

      fetched_non_deliverable = Consumers.list_consumer_events_for_consumer(consumer.id, is_deliverable: false)
      assert length(fetched_non_deliverable) == 1
      assert hd(fetched_non_deliverable).not_visible_until
    end

    test "list_consumer_events_for_consumer/2 limits the number of returned events", %{consumer: consumer} do
      for _ <- 1..5, do: ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id)

      limited_events = Consumers.list_consumer_events_for_consumer(consumer.id, limit: 2)
      assert length(limited_events) == 2
    end

    test "list_consumer_events_for_consumer/2 orders events by specified criteria", %{consumer: consumer} do
      for _ <- 1..5, do: ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id)

      events_asc = Consumers.list_consumer_events_for_consumer(consumer.id, order_by: [asc: :id])
      events_desc = Consumers.list_consumer_events_for_consumer(consumer.id, order_by: [desc: :id])

      assert Enum.map(events_asc, & &1.id) == Enum.sort(Enum.map(events_asc, & &1.id))
      assert Enum.map(events_desc, & &1.id) == Enum.sort(Enum.map(events_desc, & &1.id), :desc)
    end

    test "ack_messages/2 acks delivered events and ignores non-existent event_ids", %{consumer: consumer} do
      event1 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())
      event2 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())
      non_existent_id = Factory.uuid()

      :ok = Consumers.ack_messages(consumer, [event1.ack_id, event2.ack_id, non_existent_id])

      assert Repo.all(ConsumerEvent) == []
    end

    test "ack_messages/2 ignores events with different consumer_id", %{consumer: consumer} do
      other_consumer = ConsumersFactory.insert_consumer!(message_kind: :event)
      event1 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())

      event2 =
        ConsumersFactory.insert_consumer_event!(consumer_id: other_consumer.id, not_visible_until: DateTime.utc_now())

      :ok = Consumers.ack_messages(consumer, [event1.ack_id, event2.ack_id])

      remaining_events = Repo.all(ConsumerEvent)
      assert length(remaining_events) == 1
      assert List.first(remaining_events).id == event2.id
    end

    test "nack_messages/2 nacks events and ignores unknown event ID", %{consumer: consumer} do
      event1 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())
      event2 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())
      non_existent_id = Factory.uuid()

      :ok = Consumers.nack_messages(consumer, [event1.ack_id, event2.ack_id, non_existent_id])

      updated_event1 = Repo.get_by(ConsumerEvent, id: event1.id)
      updated_event2 = Repo.get_by(ConsumerEvent, id: event2.id)

      assert is_nil(updated_event1.not_visible_until)
      assert is_nil(updated_event2.not_visible_until)
    end

    test "nack_messages/2 does not nack events belonging to another consumer", %{consumer: consumer} do
      other_consumer = ConsumersFactory.insert_consumer!(message_kind: :event)
      event1 = ConsumersFactory.insert_consumer_event!(consumer_id: consumer.id, not_visible_until: DateTime.utc_now())

      event2 =
        ConsumersFactory.insert_consumer_event!(consumer_id: other_consumer.id, not_visible_until: DateTime.utc_now())

      :ok = Consumers.nack_messages(consumer, [event1.ack_id, event2.ack_id])

      updated_event1 = Repo.get_by(ConsumerEvent, id: event1.id)
      updated_event2 = Repo.get_by(ConsumerEvent, id: event2.id)

      assert is_nil(updated_event1.not_visible_until)
      assert DateTime.compare(updated_event2.not_visible_until, event2.not_visible_until) == :eq
    end
  end
end