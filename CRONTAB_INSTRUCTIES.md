# Instructies voor het uitvoeren van purge_inactive_users.rb

Dit document beschrijft hoe je het opgeschoonde `purge_inactive_users.rb` script inplant via `crontab` op de server waar je Discourse-instantie draait.

## Stap 1: Script plaatsen
Zorg ervoor dat het script `purge_inactive_users.rb` zich in de `/shared/` map op je server bevindt (deze map is doorgaans gekoppeld aan de `/shared` map binnen de Discourse Docker container).
Veelgebruikte locatie op de host is `/var/discourse/shared/standalone/purge_inactive_users.rb`.

*Let op: In het script staat momenteel `DRY_RUN = true`. Dit betekent dat er nog geen acties worden uitgevoerd en er alleen output naar de log wordt geschreven. Test het script eerst grondig voordat je de boolean naar `false` zet.*

## Stap 2: Handmatig testen (buiten crontab)
Voordat je de crontab aanmaakt, kun je het script handmatig testen in je Discourse container om te zien wat het zou doen:

```bash
cd /var/discourse
./launcher enter app
rails runner /shared/purge_inactive_users.rb
```
*Dit toont je precies wie een bericht krijgt en wie verwijderd/geanonimiseerd wordt (dankzij DRY_RUN = true).*

## Stap 3: Crontab instellen
Zodra je `DRY_RUN` in het script op `false` hebt gezet en klaar bent om het dagelijks te laten draaien, stel je de cronjob in op de **host** (je hoofbserver, buiten de Docker container).

Open de crontab van je server:
```bash
sudo crontab -e
```

Voeg de volgende regel toe om het script bijvoorbeeld elke nacht om 03:00 uur te laten draaien:
```cron
0 3 * * * cd /var/discourse && ./launcher run app "rails runner /shared/purge_inactive_users.rb" >> /var/log/discourse_purge.log 2>&1
```

### Uitleg van de cronjob:
- `0 3 * * *`: Draai elke nacht om 03:00 uur.
- `cd /var/discourse`: Ga naar de map waar Discourse is geïnstalleerd.
- `./launcher run app ...`: Voert een eenmalig commando uit in de `app` container. (Dit is beter dan `enter` omdat het een batch-proces is).
- `"rails runner /shared/purge_inactive_users.rb"`: Het specifieke Discourse-commando dat het script uitvoert met volledige toegang tot de database.
- `>> /var/log/discourse_purge.log 2>&1`: Zorgt ervoor dat alle output (die in het script wordt geprint met `puts`) wordt opgeslagen in een logbestand, zodat je elke dag kunt teruglezen wat er is gebeurd.

## Stap 4: Bestand en permissies controleren
Om te voorkomen dat de crontab vastloopt op rechten, zorg dat het script leesbaar is voor de gebruiker in de docker-container.
```bash
sudo chmod 644 /var/discourse/shared/standalone/purge_inactive_users.rb
```