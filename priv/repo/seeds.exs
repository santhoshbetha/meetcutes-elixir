# ============================================================================
# AUSTIN DEVELOPMENT SEED — DETERMINISTIC LOGIN ACCOUNTS
# ============================================================================
# Password for all five accounts: "Password123!"
#
#   Email                                  Name              Demographics
#   -------------------------------------  ----------------  ------------------------
#   austin.demo.alex@meetcutes.test        Alex Morgan       Male, 29, Caucasian
#   austin.demo.bella@meetcutes.test       Bella Cruz        Female, 27, Hispanic
#   austin.demo.chris@meetcutes.test       Chris Okafor      Male, 34, Black
#   austin.demo.dana@meetcutes.test        Dana Kim          Female, 31, Asian
#   austin.demo.ethan@meetcutes.test       Ethan Nakamura    Male, 24, Asian
#
# Run with:
#
#     mix run priv/repo/seeds.exs
#
# The script is idempotent for its own rows: it removes prior `austin.*`
# accounts and `ATX Seed:` locations/events before regenerating them.
# ============================================================================

defmodule Meetcutes.DevSeeds do
  @moduledoc false

  import Ecto.Query

  alias Meetcutes.Accounts.User
  alias Meetcutes.Events.Event
  alias Meetcutes.Events.Location
  alias Meetcutes.Repo

  @password "Password123!"
  @seed_email_prefix "austin."
  @location_prefix "ATX Seed:"

  @ethnicities ["Caucasian", "Black", "Asian", "Hispanic"]

  @bios [
    "Coffee-fueled product thinker exploring Austin's trail network.",
    "Live music, breakfast tacos, and long walks around Lady Bird Lake.",
    "Weekend kayaker, amateur chef, and relentless dog-park regular.",
    "Museum hopper, bookshop browser, and unapologetic taco critic.",
    "Trail runner chasing shade and the perfect post-run coffee.",
    "Rooftop sunset collector and board-game night host."
  ]

  @demo_accounts [
    %{
      email: "austin.demo.alex@meetcutes.test",
      first_name: "Alex",
      last_name: "Morgan",
      nickname: "atx_demo_alex",
      gender: "Male",
      age: 29,
      ethnicity: "Caucasian",
      latitude: 30.2672,
      longitude: -97.7431
    },
    %{
      email: "austin.demo.bella@meetcutes.test",
      first_name: "Bella",
      last_name: "Cruz",
      nickname: "atx_demo_bella",
      gender: "Female",
      age: 27,
      ethnicity: "Hispanic",
      latitude: 30.2500,
      longitude: -97.7500
    },
    %{
      email: "austin.demo.chris@meetcutes.test",
      first_name: "Chris",
      last_name: "Okafor",
      nickname: "atx_demo_chris",
      gender: "Male",
      age: 34,
      ethnicity: "Black",
      latitude: 30.4020,
      longitude: -97.7250
    },
    %{
      email: "austin.demo.dana@meetcutes.test",
      first_name: "Dana",
      last_name: "Kim",
      nickname: "atx_demo_dana",
      gender: "Female",
      age: 31,
      ethnicity: "Asian",
      latitude: 30.2980,
      longitude: -97.7050
    },
    %{
      email: "austin.demo.ethan@meetcutes.test",
      first_name: "Ethan",
      last_name: "Nakamura",
      nickname: "atx_demo_ethan",
      gender: "Male",
      age: 24,
      ethnicity: "Asian",
      latitude: 30.2669,
      longitude: -97.7729
    }
  ]

  @first_names ~w(
    Ava Liam Mia Noah Zoe Ethan Chloe Lucas Nora Mason Isla Logan Ruby Owen
    Hazel Leo Stella Caleb Violet Julian Aria Miles Luna Theo
  )

  @last_names ~w(
    Reed Carter Nguyen Brooks Patel Rivera Kim Foster Bennett Silva Chen
    Morgan Hayes Ortiz Park Coleman Singh Flores Ellis Ramos Tran Price Ward
    Delgado
  )

  @landmarks [
    %{
      name: "Dirty Sixth Street",
      street: "201 E 6th St",
      postal_code: "78701",
      latitude: 30.2676,
      longitude: -97.7387
    },
    %{
      name: "Rainey Street District",
      street: "70 Rainey St",
      postal_code: "78701",
      latitude: 30.2550,
      longitude: -97.7400
    },
    %{
      name: "South Congress",
      street: "1600 S Congress Ave",
      postal_code: "78704",
      latitude: 30.2500,
      longitude: -97.7500
    },
    %{
      name: "Zilker Park",
      street: "2100 Barton Springs Rd",
      postal_code: "78704",
      latitude: 30.2669,
      longitude: -97.7729
    },
    %{
      name: "Barton Springs Pool",
      street: "2131 William Barton Dr",
      postal_code: "78746",
      latitude: 30.2636,
      longitude: -97.7712
    },
    %{
      name: "Lady Bird Lake Trail",
      street: "Riverside Dr",
      postal_code: "78704",
      latitude: 30.2620,
      longitude: -97.7350
    },
    %{
      name: "The Domain",
      street: "11410 Century Oaks Ter",
      postal_code: "78758",
      latitude: 30.4020,
      longitude: -97.7250
    },
    %{
      name: "Mueller Lake Park",
      street: "4550 Mueller Blvd",
      postal_code: "78723",
      latitude: 30.2980,
      longitude: -97.7050
    },
    %{
      name: "UT Austin Drag",
      street: "2402 Guadalupe St",
      postal_code: "78705",
      latitude: 30.2849,
      longitude: -97.7341
    },
    %{
      name: "Texas State Capitol",
      street: "1100 Congress Ave",
      postal_code: "78701",
      latitude: 30.2747,
      longitude: -97.7404
    },
    %{
      name: "Mount Bonnell",
      street: "3800 Mount Bonnell Rd",
      postal_code: "78731",
      latitude: 30.3216,
      longitude: -97.7736
    },
    %{
      name: "Bull Creek District Park",
      street: "6701 Lakewood Dr",
      postal_code: "78731",
      latitude: 30.3500,
      longitude: -97.7800
    },
    %{
      name: "Mayfield Park",
      street: "3505 W 35th St",
      postal_code: "78703",
      latitude: 30.3100,
      longitude: -97.7600
    },
    %{
      name: "McKinney Falls State Park",
      street: "5808 McKinney Falls Pkwy",
      postal_code: "78744",
      latitude: 30.1830,
      longitude: -97.7200
    },
    %{
      name: "Q2 Stadium",
      street: "10414 McKalla Pl",
      postal_code: "78758",
      latitude: 30.3880,
      longitude: -97.7200
    },
    %{
      name: "Auditorium Shores",
      street: "900 W Riverside Dr",
      postal_code: "78704",
      latitude: 30.2600,
      longitude: -97.7500
    },
    %{
      name: "West Sixth Warehouse District",
      street: "500 W 6th St",
      postal_code: "78701",
      latitude: 30.2700,
      longitude: -97.7500
    },
    %{
      name: "Hyde Park",
      street: "4200 Speedway",
      postal_code: "78751",
      latitude: 30.3050,
      longitude: -97.7300
    },
    %{
      name: "Cherrywood",
      street: "1400 Wilshire Blvd",
      postal_code: "78722",
      latitude: 30.2900,
      longitude: -97.7100
    },
    %{
      name: "South Lamar",
      street: "1100 S Lamar Blvd",
      postal_code: "78704",
      latitude: 30.2400,
      longitude: -97.7700
    },
    %{
      name: "Sunset Valley",
      street: "5400 Brodie Ln",
      postal_code: "78745",
      latitude: 30.2300,
      longitude: -97.7900
    },
    %{
      name: "Westlake Hills",
      street: "1100 Bee Caves Rd",
      postal_code: "78746",
      latitude: 30.2900,
      longitude: -97.8000
    },
    %{
      name: "Tarrytown",
      street: "2400 Exposition Blvd",
      postal_code: "78703",
      latitude: 30.3000,
      longitude: -97.7700
    },
    %{
      name: "Lake Travis Overlook",
      street: "Commons Ford Ranch Rd",
      postal_code: "78746",
      latitude: 30.3900,
      longitude: -97.8950
    }
  ]

  @event_ideas [
    {"Coffee & Conversation",
     "A low-pressure morning meetup for good coffee and better conversation."},
    {"Sunset Social", "Golden-hour drinks, skyline views, and easy introductions."},
    {"Trail Walk & Talk", "An easy-paced walk with plenty of room to get to know each other."},
    {"Live Music Night",
     "Local bands, a relaxed crowd, and a reason to stay out a little later."},
    {"Breakfast Taco Run", "Austin's favorite morning ritual, shared over a table of tacos."},
    {"Rooftop Mixer", "A casual mixer with skyline views and a rotating circle of new faces."},
    {"Lake Day Hangout", "Bring a towel, sunscreen, and a willingness to jump in."},
    {"Board Game Social",
     "Casual games, friendly competition, and zero pressure to be an expert."},
    {"Food Truck Crawl", "Sample a few trucks and compare notes on the best bite of the night."},
    {"Bookstore Browse", "Browse the shelves, swap recommendations, and leave with a new read."},
    {"Volunteer Morning", "Give back with a small group and follow it up with coffee nearby."},
    {"Picnic in the Park", "Blankets, snacks, and a slow afternoon under the Austin sky."}
  ]

  def run do
    # Deterministic randomness keeps coordinates/ages stable between runs while
    # still producing a varied, organic-looking dataset.
    :rand.seed(:exsss, {20_261_105, 7, 11})

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # All demo accounts share the same password, so hash it once with the app's
    # native Pbkdf2 library before opening the write transaction. Hashing 28
    # passwords inside the transaction would hold a DB connection for too long.
    hashed_password = Pbkdf2.hash_pwd_salt(@password)

    {:ok, {users, events}} =
      Repo.transaction(fn ->
        delete_previous_seed_data()

        users = insert_users(now, hashed_password)
        verify_gender_distribution!(users)
        events = insert_events(users)

        {users, events}
      end)

    print_summary(users, events)
  end

  # --------------------------------------------------------------------------
  # Cleanup
  # --------------------------------------------------------------------------

  defp delete_previous_seed_data do
    seed_user_ids =
      Repo.all(
        from(u in User,
          where: like(u.email, ^"#{@seed_email_prefix}%"),
          select: u.id
        )
      )

    seed_location_ids =
      Repo.all(
        from(l in Location,
          where: like(l.name, ^"#{@location_prefix}%"),
          select: l.id
        )
      )

    if seed_user_ids != [] or seed_location_ids != [] do
      Repo.delete_all(
        from(e in Event,
          where: e.created_by in ^seed_user_ids or e.location_id in ^seed_location_ids
        )
      )
    end

    if seed_location_ids != [] do
      Repo.delete_all(from(l in Location, where: l.id in ^seed_location_ids))
    end

    if seed_user_ids != [] do
      Repo.delete_all(from(u in User, where: u.id in ^seed_user_ids))
    end

    IO.puts(
      "Cleared #{length(seed_user_ids)} prior seed users and " <>
        "#{length(seed_location_ids)} prior seed locations."
    )
  end

  # --------------------------------------------------------------------------
  # Users
  # --------------------------------------------------------------------------

  defp insert_users(now, hashed_password) do
    profiles = @demo_accounts ++ generated_profiles()

    profiles
    |> Enum.with_index()
    |> Enum.map(fn {profile, index} ->
      {latitude, longitude} = profile_coordinates(profile)
      geohash = Geohash.encode(latitude, longitude, 9)

      questionnaire_values =
        Map.new(1..14, fn question -> {"q#{question}", :rand.uniform(81) + 9} end)

      last_active_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.add(-(:rand.uniform(180) * 60), :second)

      last_seen_at =
        now
        |> DateTime.add(-(:rand.uniform(72) * 3600), :second)

      %User{
        email: profile.email,
        hashed_password: hashed_password,
        calendar_token: calendar_token(),
        first_name: profile.first_name,
        last_name: profile.last_name,
        nickname: profile.nickname,
        gender: profile.gender,
        ethnicity: profile.ethnicity,
        age: profile.age,
        birth_year: Date.utc_today().year - profile.age,
        city: "Austin",
        state: "TX",
        phone_number: phone_for(index),
        time_zone: "America/Chicago",
        bio: Enum.at(@bios, rem(index, length(@bios))),
        geohash: geohash,
        confirmed_at: now,
        is_confirmed: true,
        email_verified: true,
        id_verified: true,
        confirmation_pending: false,
        approval_pending: false,
        password_reset_pending: false,
        user_state: :active,
        is_active: true,
        is_approved: true,
        is_locked: false,
        deactivated: false,
        terms_accepted: true,
        default_coords_set: true,
        user_coords_set: false,
        exact_coords_set: false,
        email_search: true,
        phone_number_search: true,
        user_handle_search: true,
        only_hundred_miles_visibility: false,
        date_of_location: now,
        date_of_coordinates: now,
        time_of_login: last_seen_at,
        last_login_at: last_seen_at,
        last_seen_at: last_seen_at,
        last_active_at: last_active_at,
        onetime_fees_paid: true,
        onetime_fees_required: false,
        accepted_onetime_fees_amount: 0,
        questionaire_values: questionnaire_values,
        questionaire_values_set: true,
        completed_quiz: true,
        integrity_score: :rand.uniform(41) + 55,
        stewardship_score: :rand.uniform(41) + 55,
        cognitive_score: :rand.uniform(41) + 55,
        lifestyle_score: :rand.uniform(41) + 55,
        empathy_score: :rand.uniform(41) + 55,
        narcissism_flags: :rand.uniform(3) - 1,
        overall_percentile: Float.round(:rand.uniform() * 100, 1),
        settings: %{
          "visibility_preference" => "both"
        }
      }
      |> Repo.insert!()
    end)
  end

  defp calendar_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  # The discovery feed is opposite-gender scoped, so the seed must always
  # provide a balanced pool for every deterministic login account.
  defp verify_gender_distribution!(users) do
    counts = Enum.frequencies_by(users, & &1.gender)
    male_count = Map.get(counts, "Male", 0)
    female_count = Map.get(counts, "Female", 0)

    if male_count == 0 or male_count != female_count do
      raise """
      Austin seed requires an even Male/Female split so every test account has
      an opposite-gender discovery pool. Got: #{inspect(counts)}
      """
    end

    counts
  end

  defp generated_profiles do
    Enum.map(0..22, fn index ->
      first_name = Enum.at(@first_names, rem(index, length(@first_names)))
      last_name = Enum.at(@last_names, rem(index * 5, length(@last_names)))
      age = 21 + rem(index * 7, 25)

      %{
        email: "austin.seed.#{index + 1}@meetcutes.test",
        first_name: first_name,
        last_name: last_name,
        nickname: "atx_seed_#{index + 1}_#{String.downcase(first_name)}",
        gender: if(rem(index, 2) == 0, do: "Female", else: "Male"),
        age: age,
        ethnicity: Enum.at(@ethnicities, rem(index, length(@ethnicities))),
        latitude: 30.1500 + :rand.uniform() * (30.4500 - 30.1500),
        longitude: -97.9000 + :rand.uniform() * (-97.6000 - -97.9000)
      }
    end)
  end

  defp profile_coordinates(%{latitude: latitude, longitude: longitude}) do
    {Float.round(latitude, 6), Float.round(longitude, 6)}
  end

  defp phone_for(index) do
    "512555" <> String.pad_leading(Integer.to_string(1000 + index), 4, "0")
  end

  # --------------------------------------------------------------------------
  # Events
  # --------------------------------------------------------------------------

  defp insert_events(users) do
    today = Date.utc_today()

    schedule(today)
    |> Enum.with_index()
    |> Enum.map(fn {{group, date, time, duration_hours}, index} ->
      landmark = Enum.at(@landmarks, index)
      location = insert_location(landmark)
      {idea_title, idea_description} = Enum.at(@event_ideas, rem(index, length(@event_ideas)))
      creator = Enum.at(users, rem(index, length(users)))

      start_at = DateTime.new!(date, time, "Etc/UTC")
      end_at = DateTime.add(start_at, duration_hours * 3600, :second)

      attendee_count = rem(index, 4) + 1

      attendees =
        users
        |> Enum.reject(&(&1.id == creator.id))
        |> Enum.shuffle()
        |> Enum.take(attendee_count)
        |> Map.new(fn user ->
          {user.id,
           %{
             "handle" => user.nickname,
             "gender" => user.gender,
             "first_name" => user.first_name,
             "last_name" => user.last_name,
             "joined_at" => DateTime.utc_now() |> DateTime.to_iso8601()
           }}
        end)

      Repo.insert!(%Event{
        title: "#{idea_title} at #{landmark.name}",
        content:
          "#{idea_description} Meet at #{landmark.name}, #{landmark.street}, " <>
            "Austin, TX #{landmark.postal_code}. This is a seeded demo event for " <>
            "proximity, search, and registration testing.",
        location_id: location.id,
        start_at: start_at,
        end_at: end_at,
        event_date: date,
        status: "PUBLISHED",
        attendees_count: map_size(attendees),
        attendees: attendees,
        internal_notes: "Seed group: #{group}",
        created_by: creator.id
      })
    end)
  end

  defp insert_location(landmark) do
    Repo.insert!(%Location{
      name: "#{@location_prefix} #{landmark.name}",
      street: landmark.street,
      locality: "Austin",
      region: "TX",
      state: "TX",
      country: "US",
      postal_code: landmark.postal_code,
      latitude: landmark.latitude,
      longitude: landmark.longitude
    })
  end

  # 24 events split evenly across three operational timelines.
  defp schedule(today) do
    tomorrow = Date.add(today, 1)
    saturday = upcoming_saturday(today)
    sunday = Date.add(saturday, 1)

    today_slots = [
      {~T[08:00:00], 2},
      {~T[10:00:00], 2},
      {~T[12:00:00], 2},
      {~T[14:00:00], 3},
      {~T[16:00:00], 2},
      {~T[18:00:00], 3},
      {~T[20:00:00], 2},
      {~T[22:00:00], 2}
    ]

    tomorrow_slots = [
      {~T[09:00:00], 2},
      {~T[11:00:00], 2},
      {~T[13:00:00], 2},
      {~T[15:00:00], 3},
      {~T[17:00:00], 2},
      {~T[18:30:00], 2},
      {~T[20:00:00], 3},
      {~T[21:30:00], 2}
    ]

    weekend_slots = [
      {~T[09:30:00], 2},
      {~T[12:00:00], 2},
      {~T[15:00:00], 3},
      {~T[19:00:00], 3},
      {~T[10:30:00], 2},
      {~T[13:30:00], 2},
      {~T[16:30:00], 3},
      {~T[18:30:00], 2}
    ]

    weekend_dates = [
      saturday,
      saturday,
      saturday,
      saturday,
      sunday,
      sunday,
      sunday,
      sunday
    ]

    Enum.map(today_slots, fn {time, duration} ->
      {"Today", today, time, duration}
    end) ++
      Enum.map(tomorrow_slots, fn {time, duration} ->
        {"Tomorrow", tomorrow, time, duration}
      end) ++
      Enum.zip_with(weekend_dates, weekend_slots, fn date, {time, duration} ->
        {"Weekend", date, time, duration}
      end)
  end

  defp upcoming_saturday(today) do
    days_until_saturday = rem(6 - Date.day_of_week(today) + 7, 7)
    days_until_saturday = if days_until_saturday == 0, do: 7, else: days_until_saturday
    Date.add(today, days_until_saturday)
  end

  # --------------------------------------------------------------------------
  # Summary
  # --------------------------------------------------------------------------

  defp print_summary(users, events) do
    group_counts =
      events
      |> Enum.frequencies_by(& &1.internal_notes)
      |> Enum.sort_by(fn {note, _count} -> note end)

    gender_counts = Enum.frequencies_by(users, & &1.gender)

    IO.puts("""

    ============================================================================
    Austin development seed complete
    ============================================================================
    Users:  #{length(users)}
    #{Enum.map_join(gender_counts, " | ", fn {gender, count} -> "#{gender}: #{count}" end)}
    Events: #{length(events)}
    #{Enum.map_join(group_counts, "\n", fn {note, count} -> "  #{note}: #{count}" end)}

    Deterministic login accounts (password: "#{@password}")
    ----------------------------------------------------------------------------
    #{Enum.map_join(@demo_accounts, "\n", fn account -> "  #{account.email}  |  #{account.first_name} #{account.last_name}  |  #{account.gender}, #{account.age}, #{account.ethnicity}" end)}

    Coordinate footprint: lat 30.1500..30.4500, lon -97.9000..-97.6000
    ============================================================================
    """)
  end
end

Meetcutes.DevSeeds.run()
