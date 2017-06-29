# Что делает.
Скрипт выполняет раскатку проекта на dev/preview/prod стенды.
<br>
Для установки на preview/prod выполняется конфигурация окружения.
<br>
Серверная установка выполняется только на тачке с CentOS.
<br>
При установки на dev подразумевается уже настроенное окружение
<br>
_(т.е. выполняется только раскатка и конфигурация самого приложения)_
# За кулисами.
* **OS configure**:
  * create user hotdog
  * epel install / update
* **OS app:**
  * python
  * postgresql 9.6
  * nginx
  * gcc
* **Python venv:**
  * django==1.9
  * psycopg2==2.7.1
  * django-ckeditor
  * django-resized
  * pillow
  * unicorns
* **Django configure:**
  * creata app
  * deploy frontend / backend
  * migrate database
# Запуск скрипта.
Скрипт принимает следующие значения:
* -t:  install type;
* -s:  hostname;
* -f:  frontend repo name;
* -p:  postgresql password;
* -fb: frontend repo branch name;
* -bb: backend repo branch name;
* -db: database name
Ключи `-fb` `-bb` являются опциональными, если их не указать раскатка будет происходить с master ветки
Ключ `-db` необходим только для установки в дев среде _(логин/пароль зашиты в коде)_
Клюс `-p` необходим для установки в preview / prod среде _(Имя и логин базы зашиты в коде)_
# Перед первой раскаткой или после ресетапа сервера
## Установка git, обмен ключами
Для выкатки на голый сервер, перед запуском скрипта нужно следующее _(прим. для centOS)_:
* $ yum install git
* $ ssh-keygen
* $ cat ~/.ssh/id_rsa.pub _(скопировать ключ)_
* Добавить ключ в профиле github
## Для раскатки с ssl
Для корректной раскатки проекта с использование https нужно подготовить сертификаты
<br>
Описанные ниже шаги выполняются после раскатки проекта _(завершения работы deploy скрипта)_
<br>
В созданной директории **./ssl_sertificates** в хомяке СПУЗа hotdog
* $ vim private.key (создаем закрытый ключ)
* $ vim chain.crt   (создаем цепочку сертификатов: private.crt + bundle.crt)
* $ openssl dhparam -out ./dhparam.pem 4096  (генерим dhparam)
* $ systemctl start nginx
# В случае пиздеца полезно
## Проверка демонов
- $ systemctl status gunicorn
- $ systemctl status nginx
## Рестарт демонов
- $ systemctl restart gunicorn
- $ systemctl restart nginx
## Конфиг файлы
- $ vim /etc/nginx/nginx.conf
## Проверка SSL
Проверить безопасность соединения можно тут:
<br>
https://www.ssllabs.com/ssltest/analyze.html
<br>
Ожидается результат: **A+**
<br>
Посмотреть что твориться на сервере:
- $ openssl s_client -connect hostname:443 -state -debug
## Производительность
- $ ab -n 1000 -c100 https://example.com/
1000 запросов по 100 штук

# Новый релиз
## Отводим ветку с релизом
Создаем ветку с названием: **releases/_(номер релиза)_**
- $ git checkout -b branch-name
- $ git push origin branch-name
## Проблемы с миграцией данных БД
На примере изменения размера поля varchar
- $ python makemigrations
- $ vim ./backend/migration/new_migration
- $ Добавляем AlterTable + import models
```python
from django.db import migrations, models

class Migration(migrations.Migration):
 dependencies = [
  ('backend', '0002_auto_20170606_1053'),
 ]
 operations = [
  migrations.AlterField('article', 'meta_description', field=models.CharField(max_length=255))
 ]
```
