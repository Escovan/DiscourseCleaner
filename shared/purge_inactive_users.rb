# /shared/purge_inactive_users.rb

# --- INSTELLINGEN ---
WARN_0_POSTER_DAYS = 165 # ~5.5 maanden
PURGE_0_POSTER_DAYS = 180 # 6 maanden
CARE_CONTRIBUTOR_DAYS = 180 # 6 maanden
WARN_CONTRIBUTOR_DAYS = 350 # ~11.5 maanden
ANON_CONTRIBUTOR_DAYS = 365 # 12 maanden
ANON_IMPORTED_DAYS = 30 # 1 maand na waarschuwing

DRY_RUN = true # Zet op false na het testen!

puts "Start AVG-opschoning (DRY_RUN = #{DRY_RUN})..."

# Om dit script lokaal zonder Discourse te testen, mocken we de klassen niet in productie,
# maar we gaan er in dit script vanuit dat dit in de Discourse omgeving draait.
begin
  system_user = Discourse.system_user
  now = Time.now

  target_users = User.real.where(admin: false, moderator: false)

  # Helper method om de relevante datum op te halen
  def inactivity_date(user)
    user.last_seen_at || user.created_at
  end

  # Helper method om te controleren of een account gedeactiveerd of geschorst is
  def deactivated_or_suspended?(user)
    !user.active || user.suspended? || user.suspended_at.present? || user.suspended_till.present?
  end

  # --- FASE 1: DE 0-POSTERS (6 MAANDEN) ---
  puts "\n--- Fase 1: Gebruikers met 0 posts ---"

  zero_posters = target_users.joins(:user_stat).where(user_stats: { post_count: 0 })

  zero_posters.find_each do |user|
    date_to_check = inactivity_date(user)
    days_inactive = (now - date_to_check).to_i / 1.day

    if days_inactive >= PURGE_0_POSTER_DAYS
      puts "[VERWIJDER] 0-poster: #{user.username} (Inactief: #{days_inactive} dagen)"
      unless DRY_RUN
        begin
          UserDestroyer.new(system_user).destroy(user, delete_posts: true, context: 'AVG Purge 6 maanden (0 posts)')
        rescue => e
          puts "Fout bij verwijderen 0-poster #{user.username}: #{e.message}"
        end
      end
    elsif days_inactive >= WARN_0_POSTER_DAYS && user.custom_fields['purge_warning_sent'].nil?
      if deactivated_or_suspended?(user)
        puts "[OVERSLAAN WAARSCHUWING] 0-poster is gedeactiveerd/geschorst: #{user.username}"
        user.upsert_custom_fields(purge_warning_sent: 'skipped') unless DRY_RUN
      else
        puts "[WAARSCHUWING] 0-poster: #{user.username} (Inactief: #{days_inactive} dagen)"
        unless DRY_RUN
          title = "Je account wordt binnenkort verwijderd"
          raw   = "Hallo #{user.username},\n\nJe hebt al ruim 5 maanden niet ingelogd en nog geen berichten geplaatst. Over 2 weken verwijderen we je account conform ons privacybeleid. Log in om dit te voorkomen."
          PostCreator.create!(system_user, title: title, raw: raw, target_usernames: user.username, archetype: Archetype.private_message)
          user.upsert_custom_fields(purge_warning_sent: 'true')
        end
      end
    end
  end

  # --- FASE 2: DE BIJDRAGERS - REGULIER (>0 posts, wel ingelogd geweest) ---
  puts "\n--- Fase 2: Reguliere bijdragers (>0 posts) ---"

  regular_contributors = target_users.joins(:user_stat).where('user_stats.post_count > 0 AND users.last_seen_at IS NOT NULL')

  regular_contributors.find_each do |user|
    days_inactive = (now - user.last_seen_at).to_i / 1.day

    if days_inactive >= ANON_CONTRIBUTOR_DAYS
      puts "[ANONIMISEER] Reguliere bijdrager: #{user.username} (Inactief: #{days_inactive} dagen)"
      unless DRY_RUN
        begin
          UserAnonymizer.new(user, system_user).make_anonymous
        rescue => e
          puts "Fout bij anonimiseren #{user.username}: #{e.message}"
        end
      end
    elsif days_inactive >= WARN_CONTRIBUTOR_DAYS && user.custom_fields['anon_warning_sent'].nil?
      if deactivated_or_suspended?(user)
        puts "[OVERSLAAN WAARSCHUWING] Reguliere bijdrager is gedeactiveerd/geschorst: #{user.username}"
        user.upsert_custom_fields(anon_warning_sent: 'skipped') unless DRY_RUN
      else
        puts "[WAARSCHUWING] Reguliere bijdrager anonimisatie: #{user.username} (Inactief: #{days_inactive} dagen)"
        unless DRY_RUN
          title = "Je account wordt binnenkort geanonimiseerd"
          raw   = "Hallo #{user.username},\n\nJe bent al bijna een jaar niet op het forum geweest. Omdat we de privacy van onze leden, patiënten en hun naasten erg belangrijk vinden, anonimiseren we accounts na 12 maanden inactiviteit. \n\nDit betekent dat je profielnaam verandert, je persoonlijke gegevens worden gewist, maar je eerdere berichten behouden blijven (anoniem). Wil je je account behouden? Log dan binnen 2 weken in."
          PostCreator.create!(system_user, title: title, raw: raw, target_usernames: user.username, archetype: Archetype.private_message)
          user.upsert_custom_fields(anon_warning_sent: 'true')
        end
      end
    elsif days_inactive >= CARE_CONTRIBUTOR_DAYS && user.custom_fields['care_message_sent'].nil?
      if deactivated_or_suspended?(user)
        puts "[OVERSLAAN ZORGBERICHT] Reguliere bijdrager is gedeactiveerd/geschorst: #{user.username}"
        user.upsert_custom_fields(care_message_sent: 'skipped') unless DRY_RUN
      else
        puts "[ZORGBERICHT] Reguliere bijdrager: #{user.username} (Inactief: #{days_inactive} dagen)"
        unless DRY_RUN
          title = "We missen je op het forum"
          raw   = "Hallo #{user.username},\n\nWe zagen dat je al een half jaar niet bent geweest. We hopen dat alles goed met je gaat! Weet dat je altijd welkom bent om weer mee te praten of gewoon mee te lezen."
          PostCreator.create!(system_user, title: title, raw: raw, target_usernames: user.username, archetype: Archetype.private_message)
          user.upsert_custom_fields(care_message_sent: 'true')
        end
      end
    end
  end


  # --- FASE 3: GEÏMPORTEERDE BIJDRAGERS (>0 posts, nooit ingelogd) ---
  puts "\n--- Fase 3: Geïmporteerde bijdragers (Nooit ingelogd) ---"

  imported_contributors = target_users.joins(:user_stat).where('user_stats.post_count > 0 AND users.last_seen_at IS NULL')

  imported_contributors.find_each do |user|
    warning_date_str = user.custom_fields['imported_warning_sent_at']

    if warning_date_str
      warning_date = Time.parse(warning_date_str)
      days_since_warning = (now - warning_date).to_i / 1.day

      if days_since_warning >= ANON_IMPORTED_DAYS
        puts "[ANONIMISEER] Geïmporteerde bijdrager: #{user.username} (Geen login #{days_since_warning} dagen na melding)"
        unless DRY_RUN
          begin
            UserAnonymizer.new(user, system_user).make_anonymous
          rescue => e
            puts "Fout bij anonimiseren #{user.username}: #{e.message}"
          end
        end
      end
    else
      puts "[WELKOM/WAARSCHUWING] Geïmporteerde bijdrager: #{user.username}"
      unless DRY_RUN
        title = "Welkom op het nieuwe forum! Belangrijke privacy-update"
        raw   = "Hallo #{user.username},\n\nZoals je misschien weet zijn we onlangs overgegaan op een nieuw forum. Je account en eerdere waardevolle bijdragen zijn netjes meeverhuisd!\n\nVanwege de AVG en om de privacy van onze leden te beschermen, schonen we inactieve accounts op. Omdat je sinds de verhuizing nog niet hebt ingelogd, willen we je vragen of je je account wilt behouden. \n\nAls we de komende maand (30 dagen) geen nieuwe login van je zien, zullen we je account anonimiseren. Je eerdere berichten blijven anoniem behouden, maar je accountgegevens worden verwijderd. \n\nWe hopen je snel weer te zien!"
        PostCreator.create!(system_user, title: title, raw: raw, target_usernames: user.username, archetype: Archetype.private_message)
        user.upsert_custom_fields(imported_warning_sent_at: now.to_s)
      end
    end
  end

rescue NameError => e
  puts "Discourse omgeving niet gedetecteerd, script kan hier niet volledig draaien. Fout: #{e.message}"
end

puts "\nKlaar!"
