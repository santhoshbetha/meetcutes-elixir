// Example React component consuming Phoenix API
import React, { useState, useEffect } from 'react';

interface Event {
  id: string;
  title: string;
  content: string;
  start_at: string;
  end_at: string;
  location: {
    name: string;
    latitude: number;
    longitude: number;
  };
  attendees_count: number;
}

interface EventsResponse {
  events: Event[];
  pagination: {
    total_count: number;
  };
}

const EventsList: React.FC = () => {
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchEvents();
  }, []);

  const fetchEvents = async () => {
    try {
      setLoading(true);
      // This is what your Phoenix controller returns via conn |> json(...)
      const response = await fetch('/api/events');

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      // The JSON response from your Phoenix controller
      const data: EventsResponse = await response.json();

      setEvents(data.events);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  const createEvent = async (eventData: Partial<Event>) => {
    try {
      const response = await fetch('/api/events', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${getAuthToken()}`
        },
        body: JSON.stringify({ event: eventData })
      });

      if (response.status === 201) {
        // Your Phoenix controller returns 201 Created with the new event
        const newEvent: { event: Event } = await response.json();
        setEvents(prev => [...prev, newEvent.event]);
      } else {
        throw new Error('Failed to create event');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create event');
    }
  };

  const joinEvent = async (eventId: string) => {
    try {
      const response = await fetch(`/api/events/${eventId}/join`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getAuthToken()}`
        }
      });

      if (response.ok) {
        // Your Phoenix controller returns { message: "Successfully joined the event" }
        const result = await response.json();
        alert(result.message);
        // Refresh events to show updated attendee count
        fetchEvents();
      }
    } catch (err) {
      setError('Failed to join event');
    }
  };

  // Helper function to get auth token (from localStorage, context, etc.)
  const getAuthToken = () => {
    return localStorage.getItem('authToken');
  };

  if (loading) return <div>Loading events...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      <h1>Events</h1>
      <button onClick={() => createEvent({
        title: 'New Event',
        content: 'Event description',
        start_at: new Date().toISOString(),
        end_at: new Date(Date.now() + 3600000).toISOString()
      })}>
        Create Event
      </button>

      <div className="events-list">
        {events.map(event => (
          <div key={event.id} className="event-card">
            <h3>{event.title}</h3>
            <p>{event.content}</p>
            <p>Attendees: {event.attendees_count}</p>
            <p>Location: {event.location.name}</p>
            <button onClick={() => joinEvent(event.id)}>
              Join Event
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};

export default EventsList;