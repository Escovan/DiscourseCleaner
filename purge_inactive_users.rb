# /shared/purge_inactive_users.rb

# --- INSTELLINGEN ---
WARN_DAYS = 165 # Ongeveer 5,5 maand
PURGE_DAYS = 180 # 6 maanden
DRY_RUN = true # ZET DIT OP FALSE OM ECHT ACTIE TE ONDERNEMEN

puts "Start controle van inactieve gebruikers (DRY_RUN = #{DRY_RUN})..."

system_user = Discourse.system_user
warn_threshold = WARN_DAYS.days.ago
purge_threshold = PURGE_DAYS.days.ago

# Selecteer normale gebruikers (geen admin/mod/systeem)
target_users = User.real.where(admin: false, moderator: false)

# FASE 1: Waarschuwen (tussen 165 en 180 dagen)
users_to_warn = target_users.where('last_seen_at <= ? AND last_seen_at > ?', warn_threshold, purge_threshold)
warn_count = 0

users_to_warn.each do |user|
  # Controleer via een custom_field of we al gemaild hebben om spam te voorkomen
  if user.custom_fields['purge_warning_sent'].nil?
    warn_count += 1
    puts "[WAARSCHUWING] #{user.username} (Laatst gezien: #{user.last_seen_at.to_date})"
    
    unless DRY_RUN
      begin
        title = "Belangrijk: Je account wordt binnenkort verwijderd wegens inactiviteit"
        raw = "Hallo #{user.username},\n\nJe hebt al ruim 5 maanden niet ingelogd op ons forum. Om ons systeem veilig en overzichtelijk te houden, verwijderen we accounts die 6 maanden inactief zijn.\n\nWil je je account behouden? Log dan voor #{user.last_seen_at.to_date + PURGE_DAYS.days} even in. Zodra je inlogt, annuleren we het verwijderingsproces automatisch.\n\nMet vriendelijke groet,\nHet Beheerteam"
        
        # Stuur een officieel Systeem-bericht (Triggert een e-mail naar de gebruiker)
        PostCreator.create!(system_user,
                            title: title,
                            raw: raw,
                            target_usernames: user.username,
                            archetype: Archetype.private_message)
        
        # Markeer als gewaarschuwd
        user.custom_fields['purge_warning_sent'] = 'true'
        user.save_custom_fields(true)
      rescue => e
        puts "Fout bij waarschuwen #{user.username}: #{e.message}"
      end
    end
  end
end

puts "Aantal gebruikers gewaarschuwd: #{warn_count}"

# FASE 2: Verwijderen (> 180 dagen)
users_to_purge = target_users.where('last_seen_at <= ?', purge_threshold)
purge_count = 0

users_to_purge.each do |user|
  purge_count += 1
  
  if user.post_count > 0
    puts "[ANONIMISEER] #{user.username} (heeft #{user.post_count} posts)"
    unless DRY_RUN
      begin
        UserAnonymizer.new(user, system_user).make_anonymous
      rescue => e
        puts "Fout bij anonimiseren #{user.username}: #{e.message}"
      end
    end
  else
    puts "[VERWIJDER] #{user.username} (0 posts)"
    unless DRY_RUN
      begin
        UserDestroyer.new(system_user).destroy(user, delete_posts: false, context: 'Automated 6-month inactivity purge')
      rescue => e
        puts "Fout bij verwijderen #{user.username}: #{e.message}"
      end
    end
  end
end

puts "Aantal gebruikers verwijderd/geanonimiseerd: #{purge_count}"
puts "Klaar!"
