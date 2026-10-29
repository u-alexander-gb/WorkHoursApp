import 'package:flutter/material.dart' as material;

/// The existing Russian copy is the translation key while the UI is migrated.
/// User-entered project names fall through unchanged.
String appText(material.BuildContext context, String source) {
  final language = material.Localizations.localeOf(context).languageCode;
  return appTextForLanguage(language, source);
}

String appTextForLanguage(String language, String source) {
  if (language == 'ru') return source;
  final deviation = RegExp(
      r'^(Ранний приход|Опоздание|Ранний уход|Поздний уход): (\d+) мин относительно плана$')
      .firstMatch(source);
  if (deviation != null) {
    return '${appTextForLanguage(language, deviation.group(1)!)}: '
        '${deviation.group(2)} ${appTextForLanguage(language, 'мин относительно плана')}';
  }
  final overlap = RegExp(
      r'^Рабочее время пересекается со сменой (.+) \((.+)\)\. Измените время начала или окончания\.$')
      .firstMatch(source);
  if (overlap != null) {
    return '${appTextForLanguage(language, 'Рабочее время пересекается со сменой')} '
        '${overlap.group(1)} (${overlap.group(2)}). '
        '${appTextForLanguage(language, 'Измените время начала или окончания.')}';
  }
  final rateAdded = RegExp(r'^Добавлен тариф «(.+)»: (\d+) центов/ч \((.+)\)$')
      .firstMatch(source);
  if (rateAdded != null) {
    return '${appTextForLanguage(language, 'Добавлен тариф')} «${rateAdded.group(1)}»: '
        '${rateAdded.group(2)} ${appTextForLanguage(language, 'центов/ч')} '
        '(${rateAdded.group(3)})';
  }
  for (final prefix in const [
    'Проект создан. Учёт оплаты ',
    'Учёт оплаты ',
  ]) {
    if (source.startsWith(prefix)) {
      final state = source.substring(prefix.length);
      if (state == 'включён' || state == 'выключен') {
        final created = prefix.startsWith('Проект')
            ? '${appTextForLanguage(language, 'Проект создан.')} '
            : '';
        return '$created${appTextForLanguage(language, 'Учёт оплаты')} '
            '${appTextForLanguage(language, state)}';
      }
    }
  }
  final values = _messages[source];
  if (values == null) return source;
  final index = switch (language) {
    'en' => 0,
    'uk' => 1,
    'pl' => 2,
    'es' => 3,
    'tr' => 4,
    'uz' => 5,
    _ => 0,
  };
  return values[index];
}

class AppText extends material.StatelessWidget {
  const AppText(this.data, {super.key, this.style, this.textAlign});

  final String data;
  final material.TextStyle? style;
  final material.TextAlign? textAlign;

  @override
  material.Widget build(material.BuildContext context) => material.Text(
        appText(context, data), style: style, textAlign: textAlign);
}

const _messages = <String, List<String>>{
  'Учёт рабочего времени': ['Work hours', 'Облік робочого часу', 'Ewidencja czasu pracy', 'Registro de horas', 'Çalışma saatleri', 'Ish soatlari'],
  'Меню': ['Menu', 'Меню', 'Menu', 'Menú', 'Menü', 'Menyu'],
  '© 2026 Alexander. Лицензия MIT.': ['© 2026 Alexander. MIT License.', '© 2026 Alexander. Ліцензія MIT.', '© 2026 Alexander. Licencja MIT.', '© 2026 Alexander. Licencia MIT.', '© 2026 Alexander. MIT Lisansı.', '© 2026 Alexander. MIT litsenziyasi.'],
  'Язык приложения': ['Language', 'Мова застосунку', 'Język aplikacji', 'Idioma de la aplicación', 'Uygulama dili', 'Ilova tili'],
  'Системный': ['System default', 'Системна', 'Systemowy', 'Del sistema', 'Sistem dili', 'Tizim tili'],
  'Сегодня': ['Today', 'Сьогодні', 'Dzisiaj', 'Hoy', 'Bugün', 'Bugun'],
  'План': ['Plan', 'План', 'Plan', 'Plan', 'Plan', 'Reja'],
  'Проекты': ['Projects', 'Проєкти', 'Projekty', 'Proyectos', 'Projeler', 'Loyihalar'],
  'Отчёты': ['Reports', 'Звіти', 'Raporty', 'Informes', 'Raporlar', 'Hisobotlar'],
  'О приложении': ['About', 'Про застосунок', 'O aplikacji', 'Acerca de', 'Hakkında', 'Ilova haqida'],
  'Сохранить копию': ['Save backup', 'Зберегти копію', 'Zapisz kopię', 'Guardar copia', 'Yedek kaydet', 'Nusxani saqlash'],
  'Восстановить копию': ['Restore backup', 'Відновити копію', 'Przywróć kopię', 'Restaurar copia', 'Yedeği geri yükle', 'Nusxani tiklash'],
  'Резервная копия сохранена': ['Backup saved', 'Копію збережено', 'Kopia zapisana', 'Copia guardada', 'Yedek kaydedildi', 'Nusxa saqlandi'],
  'Данные восстановлены': ['Data restored', 'Дані відновлено', 'Dane przywrócone', 'Datos restaurados', 'Veriler geri yüklendi', 'Maʼlumotlar tiklandi'],
  'Отмена': ['Cancel', 'Скасувати', 'Anuluj', 'Cancelar', 'İptal', 'Bekor qilish'],
  'Назад': ['Back', 'Назад', 'Wstecz', 'Volver', 'Geri', 'Orqaga'],
  'Сохранить': ['Save', 'Зберегти', 'Zapisz', 'Guardar', 'Kaydet', 'Saqlash'],
  'Добавить': ['Add', 'Додати', 'Dodaj', 'Añadir', 'Ekle', 'Qoʻshish'],
  'Восстановить': ['Restore', 'Відновити', 'Przywróć', 'Restaurar', 'Geri yükle', 'Tiklash'],
  'Продолжить': ['Continue', 'Продовжити', 'Kontynuuj', 'Continuar', 'Devam et', 'Davom etish'],
  'Проверить': ['Verify', 'Перевірити', 'Sprawdź', 'Verificar', 'Kontrol et', 'Tekshirish'],
  'Пароль резервной копии': ['Backup password', 'Пароль резервної копії', 'Hasło kopii zapasowej', 'Contraseña de la copia', 'Yedek parolası', 'Zaxira nusxa paroli'],
  'Открыть резервную копию': ['Open backup', 'Відкрити резервну копію', 'Otwórz kopię zapasową', 'Abrir copia', 'Yedeği aç', 'Nusxani ochish'],
  'Показать пароль': ['Show password', 'Показати пароль', 'Pokaż hasło', 'Mostrar contraseña', 'Parolayı göster', 'Parolni koʻrsatish'],
  'Новый проект': ['New project', 'Новий проєкт', 'Nowy projekt', 'Nuevo proyecto', 'Yeni proje', 'Yangi loyiha'],
  'Учитывать оплату': ['Track pay', 'Облік оплати', 'Śledź wynagrodzenie', 'Registrar pago', 'Ücreti takip et', 'Toʻlovni hisoblash'],
  'Выключено: учитываются только часы': ['Off: hours only', 'Вимкнено: лише години', 'Wyłączone: tylko godziny', 'Desactivado: solo horas', 'Kapalı: yalnızca saatler', 'Oʻchiq: faqat soatlar'],
  'Запланировать смену': ['Plan shift', 'Запланувати зміну', 'Zaplanuj zmianę', 'Planificar turno', 'Vardiya planla', 'Smenani rejalash'],
  'Проект': ['Project', 'Проєкт', 'Projekt', 'Proyecto', 'Proje', 'Loyiha'],
  'Начало': ['Start', 'Початок', 'Początek', 'Inicio', 'Başlangıç', 'Boshlanish'],
  'Ожидаемый конец': ['Expected end', 'Очікуване завершення', 'Przewidywany koniec', 'Fin previsto', 'Beklenen bitiş', 'Kutilgan tugash'],
  'Выберите тариф': ['Select rate', 'Виберіть тариф', 'Wybierz stawkę', 'Elige tarifa', 'Tarife seçin', 'Tarifni tanlang'],
  'Во сколько началась работа?': ['When did work start?', 'Коли почалася робота?', 'Kiedy zaczęła się praca?', '¿Cuándo empezó el trabajo?', 'İş ne zaman başladı?', 'Ish qachon boshlandi?'],
  'Выбрать другое время': ['Choose another time', 'Вибрати інший час', 'Wybierz inną godzinę', 'Elegir otra hora', 'Başka saat seç', 'Boshqa vaqtni tanlash'],
  'Завершить смену': ['Finish shift', 'Завершити зміну', 'Zakończ zmianę', 'Finalizar turno', 'Vardiyayı bitir', 'Smenani tugatish'],
  'Время окончания': ['End time', 'Час завершення', 'Godzina zakończenia', 'Hora de fin', 'Bitiş saati', 'Tugash vaqti'],
  'Check-out': ['Check-out', 'Check-out', 'Check-out', 'Check-out', 'Check-out', 'Check-out'],
  'Проверьте время': ['Check the time', 'Перевірте час', 'Sprawdź godzinę', 'Comprueba la hora', 'Saati kontrol edin', 'Vaqtni tekshiring'],
  'Отклонение от плана': ['Difference from plan', 'Відхилення від плану', 'Odchylenie od planu', 'Desviación del plan', 'Plandan sapma', 'Rejadan farq'],
  'Проверьте время. При необходимости укажите причину.': ['Check the time. Add a reason if needed.', 'Перевірте час. За потреби вкажіть причину.', 'Sprawdź godzinę. W razie potrzeby podaj powód.', 'Comprueba la hora. Añade un motivo si hace falta.', 'Saati kontrol edin. Gerekirse neden belirtin.', 'Vaqtni tekshiring. Zarur boʻlsa sababini yozing.'],
  'Сохранить фактическое время': ['Save actual time', 'Зберегти фактичний час', 'Zapisz rzeczywisty czas', 'Guardar hora real', 'Gerçek saati kaydet', 'Haqiqiy vaqtni saqlash'],
  'Исправить смену': ['Correct shift', 'Виправити зміну', 'Popraw zmianę', 'Corregir turno', 'Vardiyayı düzelt', 'Smenani tuzatish'],
  'Плановое начало': ['Planned start', 'Плановий початок', 'Planowany początek', 'Inicio previsto', 'Planlanan başlangıç', 'Rejadagi boshlanish'],
  'Плановый конец': ['Planned end', 'Планове завершення', 'Planowany koniec', 'Fin previsto', 'Planlanan bitiş', 'Rejadagi tugash'],
  'Тариф': ['Rate', 'Тариф', 'Stawka', 'Tarifa', 'Tarife', 'Tarif'],
  'Учтённое начало': ['Recorded start', 'Врахований початок', 'Zapisany początek', 'Inicio registrado', 'Kaydedilen başlangıç', 'Qayd etilgan boshlanish'],
  'Учтённый конец': ['Recorded end', 'Враховане завершення', 'Zapisany koniec', 'Fin registrado', 'Kaydedilen bitiş', 'Qayd etilgan tugash'],
  'Исправить': ['Correct', 'Виправити', 'Popraw', 'Corregir', 'Düzelt', 'Tuzatish'],
  'Изменить план': ['Edit plan', 'Змінити план', 'Edytuj plan', 'Editar plan', 'Planı düzenle', 'Rejani oʻzgartirish'],
  'Отменить': ['Cancel', 'Скасувати', 'Anuluj', 'Cancelar', 'İptal et', 'Bekor qilish'],
  'История': ['History', 'Історія', 'Historia', 'Historial', 'Geçmiş', 'Tarix'],
  'История смены': ['Shift history', 'Історія зміни', 'Historia zmiany', 'Historial del turno', 'Vardiya geçmişi', 'Smena tarixi'],
  'История проекта': ['Project history', 'Історія проєкту', 'Historia projektu', 'Historial del proyecto', 'Proje geçmişi', 'Loyiha tarixi'],
  'Отменить плановую смену?': ['Cancel planned shift?', 'Скасувати заплановану зміну?', 'Anulować zaplanowaną zmianę?', '¿Cancelar el turno planificado?', 'Planlanan vardiya iptal edilsin mi?', 'Rejalangan smena bekor qilinsinmi?'],
  'Отменить смену': ['Cancel shift', 'Скасувати зміну', 'Anuluj zmianę', 'Cancelar turno', 'Vardiyayı iptal et', 'Smenani bekor qilish'],
  'Восстановить данные?': ['Restore data?', 'Відновити дані?', 'Przywrócić dane?', '¿Restaurar datos?', 'Veriler geri yüklensin mi?', 'Maʼlumotlar tiklansinmi?'],
  'На сегодня нет смен.': ['No shifts today.', 'Сьогодні змін немає.', 'Brak zmian na dziś.', 'No hay turnos hoy.', 'Bugün vardiya yok.', 'Bugun smena yoʻq.'],
  'Плановое начало прошло. Подтвердите прибытие.': ['Planned start has passed. Confirm arrival.', 'Плановий початок минув. Підтвердьте прибуття.', 'Planowany początek minął. Potwierdź przybycie.', 'Ya pasó la hora de inicio. Confirma tu llegada.', 'Planlanan başlangıç geçti. Varışınızı onaylayın.', 'Rejadagi boshlanish oʻtdi. Kelganingizni tasdiqlang.'],
  'Плановое начало прошло. Сделайте check-in.': ['Planned start has passed. Check in.', 'Плановий початок минув. Зробіть check-in.', 'Planowany początek minął. Zrób check-in.', 'Ya pasó la hora de inicio. Haz check-in.', 'Planlanan başlangıç geçti. Check-in yapın.', 'Rejadagi boshlanish oʻtdi. Check-in qiling.'],
  'Плановый конец прошёл. Сделайте check-out.': ['Planned end has passed. Check out.', 'Планове завершення минуло. Зробіть check-out.', 'Planowany koniec minął. Zrób check-out.', 'Ya pasó la hora de fin. Haz check-out.', 'Planlanan bitiş geçti. Check-out yapın.', 'Rejadagi tugash oʻtdi. Check-out qiling.'],
  'После check-in перенести или отменить день через план нельзя.': ['After check-in, this day cannot be moved or cancelled in the plan.', 'Після check-in день не можна перенести чи скасувати в плані.', 'Po check-in nie można przenieść ani anulować dnia w planie.', 'Tras el check-in no puedes mover ni cancelar el día en el plan.', 'Check-in sonrası gün planda taşınamaz veya iptal edilemez.', 'Check-in dan keyin rejadagi kunni koʻchirish yoki bekor qilish mumkin emas.'],
  'Приложение для личного учёта рабочих смен, часов и тарифов.': ['Personal tracking of work shifts, hours and rates.', 'Особистий облік робочих змін, годин і тарифів.', 'Osobista ewidencja zmian, godzin i stawek.', 'Registro personal de turnos, horas y tarifas.', 'Vardiya, saat ve ücretleri kişisel takip.', 'Smenalar, soatlar va tariflarni shaxsiy hisobga olish.'],
  'Создайте проект, затем добавьте его тарифы.': ['Create a project, then add its rates.', 'Створіть проєкт, потім додайте його тарифи.', 'Utwórz projekt, a potem dodaj stawki.', 'Crea un proyecto y luego añade tarifas.', 'Bir proje oluşturun, ardından tarifeleri ekleyin.', 'Loyiha yarating, soʻng uning tariflarini qoʻshing.'],
  'Создатель: Alexander (u-alexander-gb).': ['Created by Alexander (u-alexander-gb).', 'Створив Alexander (u-alexander-gb).', 'Autor: Alexander (u-alexander-gb).', 'Creado por Alexander (u-alexander-gb).', 'Geliştiren: Alexander (u-alexander-gb).', 'Yaratuvchi: Alexander (u-alexander-gb).'],
  'Список': ['List', 'Список', 'Lista', 'Lista', 'Liste', 'Roʻyxat'],
  'Календарь': ['Calendar', 'Календар', 'Kalendarz', 'Calendario', 'Takvim', 'Taqvim'],
  'План на месяц': ['Monthly plan', 'План на місяць', 'Plan miesięczny', 'Plan mensual', 'Aylık plan', 'Oylik reja'],
  'План на неделю': ['Weekly plan', 'План на тиждень', 'Plan tygodniowy', 'Plan semanal', 'Haftalık plan', 'Haftalik reja'],
  'Добавить смену': ['Add shift', 'Додати зміну', 'Dodaj zmianę', 'Añadir turno', 'Vardiya ekle', 'Smena qoʻshish'],
  'На выбранный день смен нет.': ['No shifts on this day.', 'На вибраний день змін немає.', 'Brak zmian w tym dniu.', 'No hay turnos ese día.', 'Bu gün vardiya yok.', 'Bu kunda smena yoʻq.'],
  'Добавить проект': ['Add project', 'Додати проєкт', 'Dodaj projekt', 'Añadir proyecto', 'Proje ekle', 'Loyiha qoʻshish'],
  'Добавить тариф': ['Add rate', 'Додати тариф', 'Dodaj stawkę', 'Añadir tarifa', 'Tarife ekle', 'Tarif qoʻshish'],
  'День': ['Day', 'День', 'Dzień', 'Día', 'Gün', 'Kun'],
  'Неделя': ['Week', 'Тиждень', 'Tydzień', 'Semana', 'Hafta', 'Hafta'],
  'Месяц': ['Month', 'Місяць', 'Miesiąc', 'Mes', 'Ay', 'Oy'],
  'Выбранный период': ['Custom period', 'Вибраний період', 'Wybrany okres', 'Período elegido', 'Seçilen dönem', 'Tanlangan davr'],
  'Завершённых смен нет.': ['No completed shifts.', 'Завершених змін немає.', 'Brak zakończonych zmian.', 'No hay turnos completados.', 'Tamamlanan vardiya yok.', 'Tugallangan smena yoʻq.'],
  'Сохранить отчёт CSV': ['Save CSV report', 'Зберегти звіт CSV', 'Zapisz raport CSV', 'Guardar informe CSV', 'CSV raporunu kaydet', 'CSV hisobotni saqlash'],
  'Отчёт CSV сохранён': ['CSV report saved', 'Звіт CSV збережено', 'Raport CSV zapisany', 'Informe CSV guardado', 'CSV raporu kaydedildi', 'CSV hisobot saqlandi'],
  'Предварительный check-in': ['Early check-in', 'Попередній check-in', 'Wstępny check-in', 'Check-in previo', 'Ön check-in', 'Dastlabki check-in'],
  'Подтвердить начало': ['Confirm start', 'Підтвердити початок', 'Potwierdź początek', 'Confirmar inicio', 'Başlangıcı onayla', 'Boshlanishni tasdiqlash'],
  'Идёт работа': ['Working', 'Робота триває', 'Praca trwa', 'Trabajando', 'Çalışıyor', 'Ish davom etmoqda'],
  'Завершена': ['Completed', 'Завершено', 'Zakończona', 'Completado', 'Tamamlandı', 'Tugallandi'],
  'Отменена': ['Cancelled', 'Скасовано', 'Anulowana', 'Cancelado', 'İptal edildi', 'Bekor qilindi'],
  'Пароль': ['Password', 'Пароль', 'Hasło', 'Contraseña', 'Parola', 'Parol'],
  'Повторите пароль': ['Repeat password', 'Повторіть пароль', 'Powtórz hasło', 'Repite la contraseña', 'Parolayı tekrarla', 'Parolni takrorlang'],
  'Пароли не совпадают': ['Passwords do not match', 'Паролі не збігаються', 'Hasła nie są takie same', 'Las contraseñas no coinciden', 'Parolalar eşleşmiyor', 'Parollar mos kelmaydi'],
  'Название работы или проекта': ['Job or project name', 'Назва роботи або проєкту', 'Nazwa pracy lub projektu', 'Nombre del trabajo o proyecto', 'İş veya proje adı', 'Ish yoki loyiha nomi'],
  'Название тарифа': ['Rate name', 'Назва тарифу', 'Nazwa stawki', 'Nombre de la tarifa', 'Tarife adı', 'Tarif nomi'],
  'Евро за час': ['Euros per hour', 'Євро за годину', 'Euro za godzinę', 'Euros por hora', 'Saat başına avro', 'Soatiga yevro'],
  'Неоплачиваемый перерыв, минуты': ['Unpaid break, minutes', 'Неоплачувана перерва, хвилини', 'Niepłatna przerwa, minuty', 'Descanso no pagado, minutos', 'Ücretsiz mola, dakika', 'Toʻlanmaydigan tanaffus, daqiqa'],
  'Причина (необязательно)': ['Reason (optional)', 'Причина (необовʼязково)', 'Powód (opcjonalnie)', 'Motivo (opcional)', 'Neden (isteğe bağlı)', 'Sabab (ixtiyoriy)'],
  'Причина исправления': ['Reason for correction', 'Причина виправлення', 'Powód poprawki', 'Motivo de corrección', 'Düzeltme nedeni', 'Tuzatish sababi'],
  'Например: ошибся во времени': ['For example: entered the wrong time', 'Наприклад: помилився з часом', 'Na przykład: błędna godzina', 'Por ejemplo: hora incorrecta', 'Örneğin: saati yanlış girdim', 'Masalan: vaqtni xato kiritdim'],
  'Причина отмены': ['Reason for cancellation', 'Причина скасування', 'Powód anulowania', 'Motivo de cancelación', 'İptal nedeni', 'Bekor qilish sababi'],
  'Только часы, без денежных сумм': ['Hours only, without amounts', 'Лише години, без сум', 'Tylko godziny, bez kwot', 'Solo horas, sin importes', 'Yalnızca saatler, tutar yok', 'Faqat soatlar, pul summasisiz'],
  'Часы и начисления по тарифу': ['Hours and pay by rate', 'Години та оплата за тарифом', 'Godziny i płaca według stawki', 'Horas y pago por tarifa', 'Saatler ve tarifeye göre ücret', 'Soatlar va tarif boʻyicha toʻlov'],
  'Ранний приход': ['Early arrival', 'Ранній прихід', 'Wczesne przyjście', 'Llegada temprana', 'Erken geliş', 'Erta kelish'],
  'Опоздание': ['Late arrival', 'Запізнення', 'Spóźnienie', 'Llegada tarde', 'Geç kalma', 'Kechikish'],
  'Ранний уход': ['Early departure', 'Ранній вихід', 'Wcześniejsze wyjście', 'Salida temprana', 'Erken çıkış', 'Erta ketish'],
  'Поздний уход': ['Late departure', 'Пізній вихід', 'Późniejsze wyjście', 'Salida tardía', 'Geç çıkış', 'Kech ketish'],
  'смен': ['shifts', 'змін', 'zmian', 'turnos', 'vardiya', 'smena'],
  ' ч ': ['h ', ' год ', ' godz. ', ' h ', ' sa ', ' soat '],
  ' ч': ['h', ' год', ' godz.', ' h', ' sa', ' soat'],
  ' мин': [' min', ' хв', ' min', ' min', ' dk', ' daq'],
  ' д ': ['d ', ' д ', ' d ', ' d ', ' g ', ' kun '],
  '/ч': ['/h', '/год', '/godz.', '/h', '/sa', '/soat'],
  'По плану': ['Planned', 'За планом', 'Zgodnie z planem', 'Según el plan', 'Plana göre', 'Rejaga koʻra'],
  'Сейчас': ['Now', 'Зараз', 'Teraz', 'Ahora', 'Şimdi', 'Hozir'],
  'Время': ['Time', 'Час', 'Czas', 'Tiempo', 'Zaman', 'Vaqt'],
  'планового конца': ['planned end', 'планового завершення', 'planowanego końca', 'fin previsto', 'planlanan bitiş', 'rejadagi tugash'],
  'начала': ['start', 'початку', 'początku', 'inicio', 'başlangıç', 'boshlanish'],
  'прошло на': ['passed by', 'минув на', 'minął o', 'ha pasado por', 'geçti', 'oʻtdi'],
  'До': ['Until', 'До', 'Do', 'Hasta', 'Kalan', 'Gacha'],
  'Предв. check-in': ['Early check-in', 'Попер. check-in', 'Wstępny check-in', 'Check-in previo', 'Ön check-in', 'Dastlabki check-in'],
  'Учтённое время': ['Recorded time', 'Врахований час', 'Zapisany czas', 'Tiempo registrado', 'Kaydedilen süre', 'Qayd etilgan vaqt'],
  'Сумма': ['Total', 'Сума', 'Suma', 'Importe', 'Tutar', 'Summa'],
  'мин относительно плана': ['min from plan', 'хв від плану', 'min względem planu', 'min respecto al plan', 'dk plana göre', 'daq rejadan farq'],
  'Запомните пароль: без него восстановить копию нельзя. Минимум 12 символов.': ['Remember this password: the backup cannot be restored without it. At least 12 characters.', 'Запамʼятайте пароль: без нього копію не відновити. Щонайменше 12 символів.', 'Zapamiętaj hasło: bez niego nie przywrócisz kopii. Co najmniej 12 znaków.', 'Recuerda la contraseña: sin ella no podrás restaurar la copia. Mínimo 12 caracteres.', 'Parolayı unutmayın: yedek onsuz geri yüklenemez. En az 12 karakter.', 'Parolni eslab qoling: usiz nusxani tiklab boʻlmaydi. Kamida 12 belgi.'],
  'Введите пароль для проверки и просмотра копии.': ['Enter the password to verify and preview the backup.', 'Введіть пароль, щоб перевірити й переглянути копію.', 'Wpisz hasło, aby sprawdzić i przejrzeć kopię.', 'Introduce la contraseña para verificar y ver la copia.', 'Yedeği doğrulamak ve önizlemek için parolayı girin.', 'Nusxani tekshirish va koʻrish uchun parolni kiriting.'],
  'Файл': ['File', 'Файл', 'Plik', 'Archivo', 'Dosya', 'Fayl'],
  'Создан': ['Created', 'Створено', 'Utworzono', 'Creado', 'Oluşturuldu', 'Yaratilgan'],
  'Проектов': ['Projects', 'Проєктів', 'Projektów', 'Proyectos', 'Projeler', 'Loyihalar'],
  'тарифов': ['rates', 'тарифів', 'stawek', 'tarifas', 'tarifeler', 'tariflar'],
  'Смен': ['Shifts', 'Змін', 'Zmian', 'Turnos', 'Vardiyalar', 'Smenalar'],
  'событий': ['events', 'подій', 'zdarzeń', 'eventos', 'olaylar', 'hodisalar'],
  'Пароль и целостность проверены.': ['Password and integrity verified.', 'Пароль і цілісність перевірено.', 'Hasło i integralność sprawdzone.', 'Contraseña e integridad verificadas.', 'Parola ve bütünlük doğrulandı.', 'Parol va yaxlitlik tekshirildi.'],
  'Старая копия без шифрования.': ['Older unencrypted backup.', 'Стара незашифрована копія.', 'Starsza niezaszyfrowana kopia.', 'Copia antigua sin cifrar.', 'Eski şifrelenmemiş yedek.', 'Eski shifrlanmagan nusxa.'],
  'Текущие данные будут заменены. Сначала сохраните их копию.': ['Current data will be replaced. Save a backup first.', 'Поточні дані буде замінено. Спочатку збережіть їхню копію.', 'Bieżące dane zostaną zastąpione. Najpierw zapisz ich kopię.', 'Se reemplazarán los datos actuales. Guarda una copia antes.', 'Mevcut veriler değiştirilecek. Önce yedekleyin.', 'Hozirgi maʼlumotlar almashtiriladi. Avval nusxa saqlang.'],
  'Плановая смена отменена. Причина': ['Planned shift cancelled. Reason', 'Заплановану зміну скасовано. Причина', 'Zaplanowana zmiana anulowana. Powód', 'Turno planificado cancelado. Motivo', 'Planlanan vardiya iptal edildi. Neden', 'Rejalangan smena bekor qilindi. Sabab'],
  'не указана': ['not provided', 'не вказана', 'nie podano', 'no indicado', 'belirtilmedi', 'koʻrsatilmagan'],
  'Причина': ['Reason', 'Причина', 'Powód', 'Motivo', 'Neden', 'Sabab'],
  'Смена запланирована': ['Shift planned', 'Зміну заплановано', 'Zmiana zaplanowana', 'Turno planificado', 'Vardiya planlandı', 'Smena rejalandi'],
  'Начало подтверждено': ['Start confirmed', 'Початок підтверджено', 'Początek potwierdzony', 'Inicio confirmado', 'Başlangıç onaylandı', 'Boshlanish tasdiqlandi'],
  'Смена завершена': ['Shift completed', 'Зміну завершено', 'Zmiana zakończona', 'Turno completado', 'Vardiya tamamlandı', 'Smena tugallandi'],
  'Ставка в центах': ['Rate in cents', 'Ставка в центах', 'Stawka w centach', 'Tarifa en céntimos', 'Sent cinsinden ücret', 'Sentdagi tarif'],
  'Валюта': ['Currency', 'Валюта', 'Waluta', 'Moneda', 'Para birimi', 'Valyuta'],
  'Перерыв, мин': ['Break, min', 'Перерва, хв', 'Przerwa, min', 'Descanso, min', 'Mola, dk', 'Tanaffus, daq'],
  'Параметры смены исправлены': ['Shift details corrected', 'Параметри зміни виправлено', 'Dane zmiany poprawione', 'Datos del turno corregidos', 'Vardiya bilgileri düzeltildi', 'Smena tafsilotlari tuzatildi'],
  'Неверный формат резервной копии': ['Invalid backup format', 'Невірний формат копії', 'Nieprawidłowy format kopii', 'Formato de copia no válido', 'Geçersiz yedek biçimi', 'Nusxa formati notoʻgʻri'],
  'Пароль должен содержать минимум 12 символов': ['Password must have at least 12 characters', 'Пароль має містити щонайменше 12 символів', 'Hasło musi mieć co najmniej 12 znaków', 'La contraseña debe tener al menos 12 caracteres', 'Parola en az 12 karakter olmalı', 'Parol kamida 12 belgidan iborat boʻlishi kerak'],
  'Неподдерживаемый формат защищённой копии': ['Unsupported encrypted backup format', 'Непідтримуваний формат захищеної копії', 'Nieobsługiwany format zaszyfrowanej kopii', 'Formato de copia cifrada no compatible', 'Desteklenmeyen şifreli yedek biçimi', 'Shifrlangan nusxa formati qoʻllab-quvvatlanmaydi'],
  'Повреждён заголовок резервной копии': ['Backup header is damaged', 'Заголовок копії пошкоджено', 'Nagłówek kopii jest uszkodzony', 'Cabecera de la copia dañada', 'Yedek başlığı bozuk', 'Nusxa sarlavhasi buzilgan'],
  'Неверный пароль или файл повреждён': ['Wrong password or damaged file', 'Невірний пароль або файл пошкоджено', 'Błędne hasło lub uszkodzony plik', 'Contraseña incorrecta o archivo dañado', 'Yanlış parola veya bozuk dosya', 'Parol notoʻgʻri yoki fayl buzilgan'],
  'Повреждён файл резервной копии': ['Backup file is damaged', 'Файл копії пошкоджено', 'Plik kopii jest uszkodzony', 'Archivo de copia dañado', 'Yedek dosyası bozuk', 'Nusxa fayli buzilgan'],
  'Файл резервной копии слишком большой': ['Backup file is too large', 'Файл копії завеликий', 'Plik kopii jest zbyt duży', 'El archivo de copia es demasiado grande', 'Yedek dosyası çok büyük', 'Nusxa fayli juda katta'],
  'Неверная дата резервной копии': ['Invalid backup date', 'Невірна дата копії', 'Nieprawidłowa data kopii', 'Fecha de copia no válida', 'Geçersiz yedek tarihi', 'Nusxa sanasi notoʻgʻri'],
  'В копии отсутствует таблица данных': ['Backup is missing a data table', 'У копії бракує таблиці даних', 'W kopii brakuje tabeli danych', 'Falta una tabla de datos en la copia', 'Yedekte veri tablosu eksik', 'Nusxada maʼlumotlar jadvali yoʻq'],
  'В копии есть неверные данные': ['Backup contains invalid data', 'У копії є невірні дані', 'Kopia zawiera nieprawidłowe dane', 'La copia contiene datos no válidos', 'Yedekte geçersiz veriler var', 'Nusxada notoʻgʻri maʼlumotlar bor'],
  'Повреждена история исправлений': ['Correction history is damaged', 'Історію виправлень пошкоджено', 'Historia poprawek jest uszkodzona', 'Historial de correcciones dañado', 'Düzeltme geçmişi bozuk', 'Tuzatishlar tarixi buzilgan'],
  'Название проекта обязательно': ['Project name is required', 'Потрібна назва проєкту', 'Nazwa projektu jest wymagana', 'Se requiere el nombre del proyecto', 'Proje adı gerekli', 'Loyiha nomi kerak'],
  'Проект не найден': ['Project not found', 'Проєкт не знайдено', 'Nie znaleziono projektu', 'Proyecto no encontrado', 'Proje bulunamadı', 'Loyiha topilmadi'],
  'Проверьте название и сумму тарифа': ['Check the rate name and amount', 'Перевірте назву й суму тарифу', 'Sprawdź nazwę i kwotę stawki', 'Comprueba el nombre y el importe de la tarifa', 'Tarife adını ve tutarını kontrol edin', 'Tarif nomi va summasini tekshiring'],
  'Конец плана должен быть позже начала': ['Planned end must be after start', 'Планове завершення має бути після початку', 'Planowany koniec musi być po początku', 'El fin previsto debe ser posterior al inicio', 'Planlanan bitiş başlangıçtan sonra olmalı', 'Rejadagi tugash boshlanishdan keyin boʻlishi kerak'],
  'Укажите причину отмены': ['Enter a reason for cancellation', 'Вкажіть причину скасування', 'Podaj powód anulowania', 'Indica el motivo de cancelación', 'İptal nedenini girin', 'Bekor qilish sababini kiriting'],
  'Выберите тариф для проекта с учётом оплаты': ['Select a rate for this pay-tracked project', 'Виберіть тариф для проєкту з обліком оплати', 'Wybierz stawkę dla projektu z płacą', 'Elige tarifa para este proyecto con pago', 'Ücret takip edilen proje için tarife seçin', 'Toʻlov hisoblanadigan loyiha uchun tarif tanlang'],
  'В этом проекте учёт оплаты выключен': ['Pay tracking is off for this project', 'У цьому проєкті облік оплати вимкнено', 'Śledzenie płacy jest wyłączone w tym projekcie', 'El registro de pago está desactivado en este proyecto', 'Bu projede ücret takibi kapalı', 'Bu loyihada toʻlov hisobi oʻchiq'],
  'Начало работы не может быть в будущем': ['Work start cannot be in the future', 'Початок роботи не може бути в майбутньому', 'Początek pracy nie może być w przyszłości', 'El inicio del trabajo no puede estar en el futuro', 'İş başlangıcı gelecekte olamaz', 'Ish boshlanishi kelajakda boʻla olmaydi'],
  'Перерыв не может быть отрицательным': ['Break cannot be negative', 'Перерва не може бути відʼємною', 'Przerwa nie może być ujemna', 'El descanso no puede ser negativo', 'Mola negatif olamaz', 'Tanaffus manfiy boʻla olmaydi'],
  'Проверьте время окончания и перерыв': ['Check end time and break', 'Перевірте час завершення й перерву', 'Sprawdź koniec i przerwę', 'Comprueba la hora de fin y el descanso', 'Bitiş saatini ve molayı kontrol edin', 'Tugash vaqti va tanaffusni tekshiring'],
  'После check-in нельзя перенести смену на другой день': ['After check-in, the shift cannot move to another day', 'Після check-in зміну не можна перенести на інший день', 'Po check-in nie można przenieść zmiany na inny dzień', 'Tras el check-in no puedes mover el turno a otro día', 'Check-in sonrası vardiya başka güne taşınamaz', 'Check-in dan keyin smenani boshqa kunga koʻchirib boʻlmaydi'],
  'После check-in нельзя изменить день окончания': ['After check-in, the end day cannot change', 'Після check-in день завершення не можна змінити', 'Po check-in nie można zmienić dnia zakończenia', 'Tras el check-in no puedes cambiar el día de fin', 'Check-in sonrası bitiş günü değiştirilemez', 'Check-in dan keyin tugash kunini oʻzgartirib boʻlmaydi'],
  'Смена не найдена': ['Shift not found', 'Зміну не знайдено', 'Nie znaleziono zmiany', 'Turno no encontrado', 'Vardiya bulunamadı', 'Smena topilmadi'],
  'Эту смену нельзя исправить в текущем состоянии': ['This shift cannot be corrected in its current state', 'Цю зміну не можна виправити в поточному стані', 'Nie można poprawić zmiany w obecnym stanie', 'No se puede corregir este turno en su estado actual', 'Bu vardiya mevcut durumda düzeltilemez', 'Bu smenani hozirgi holatda tuzatib boʻlmaydi'],
  'Активная смена ещё не завершена': ['Active shift has not ended yet', 'Активна зміна ще не завершена', 'Aktywna zmiana jeszcze się nie skończyła', 'El turno activo aún no ha terminado', 'Etkin vardiya henüz bitmedi', 'Faol smena hali tugamagan'],
  'Тариф этого проекта не найден': ['Rate for this project not found', 'Тариф цього проєкту не знайдено', 'Nie znaleziono stawki tego projektu', 'Tarifa del proyecto no encontrada', 'Bu projenin tarifesi bulunamadı', 'Bu loyiha tarifi topilmadi'],
  'Укажите причину исправления': ['Enter a reason for correction', 'Вкажіть причину виправлення', 'Podaj powód poprawki', 'Indica el motivo de corrección', 'Düzeltme nedenini girin', 'Tuzatish sababini kiriting'],
  'Состояние смены изменилось. Обновите экран.': ['Shift status changed. Refresh the screen.', 'Стан зміни змінився. Оновіть екран.', 'Stan zmiany się zmienił. Odśwież ekran.', 'El estado del turno cambió. Actualiza la pantalla.', 'Vardiya durumu değişti. Ekranı yenileyin.', 'Smena holati oʻzgardi. Ekranni yangilang.'],
  'Укажите перерыв в минутах': ['Enter break in minutes', 'Вкажіть перерву у хвилинах', 'Podaj przerwę w minutach', 'Indica el descanso en minutos', 'Molayı dakika olarak girin', 'Tanaffusni daqiqada kiriting'],
  'Укажите сумму, например 15,50': ['Enter an amount, for example 15.50', 'Вкажіть суму, наприклад 15,50', 'Podaj kwotę, np. 15,50', 'Indica un importe, por ejemplo 15,50', 'Tutar girin, örneğin 15,50', 'Summani kiriting, masalan 15,50'],
  'Сначала добавьте тариф для проекта': ['Add a rate to the project first', 'Спочатку додайте тариф до проєкту', 'Najpierw dodaj stawkę do projektu', 'Primero añade una tarifa al proyecto', 'Önce projeye tarife ekleyin', 'Avval loyihaga tarif qoʻshing'],
  'Напоминание не назначено. Проверьте разрешения.': ['Reminder was not scheduled. Check permissions.', 'Нагадування не призначено. Перевірте дозволи.', 'Nie zaplanowano przypomnienia. Sprawdź uprawnienia.', 'No se programó el recordatorio. Comprueba permisos.', 'Hatırlatıcı ayarlanmadı. İzinleri kontrol edin.', 'Eslatma belgilanmadi. Ruxsatlarni tekshiring.'],
  'Напоминание может прийти с задержкой.': ['Reminder may arrive late.', 'Нагадування може надійти із затримкою.', 'Przypomnienie może się spóźnić.', 'El recordatorio puede llegar tarde.', 'Hatırlatıcı gecikebilir.', 'Eslatma kech kelishi mumkin.'],
  'План сохранён, но напоминание о check-in не назначено': ['Plan saved, but check-in reminder was not scheduled', 'План збережено, але нагадування про check-in не призначено', 'Plan zapisany, ale nie zaplanowano przypomnienia o check-in', 'Plan guardado, pero no se programó el aviso de check-in', 'Plan kaydedildi ancak check-in hatırlatıcısı ayarlanmadı', 'Reja saqlandi, lekin check-in eslatmasi belgilanmadi'],
  'Начало сохранено, но напоминание о check-out не назначено': ['Start saved, but check-out reminder was not scheduled', 'Початок збережено, але нагадування про check-out не призначено', 'Początek zapisany, ale nie zaplanowano przypomnienia o check-out', 'Inicio guardado, pero no se programó el aviso de check-out', 'Başlangıç kaydedildi ancak check-out hatırlatıcısı ayarlanmadı', 'Boshlanish saqlandi, lekin check-out eslatmasi belgilanmadi'],
  'Время изменено, но напоминание не назначено': ['Time changed, but reminder was not scheduled', 'Час змінено, але нагадування не призначено', 'Godzina zmieniona, ale nie zaplanowano przypomnienia', 'Hora cambiada, pero no se programó el aviso', 'Saat değiştirildi ancak hatırlatıcı ayarlanmadı', 'Vaqt oʻzgardi, lekin eslatma belgilanmadi'],
  'Рабочее время пересекается со сменой': ['Work time overlaps with shift', 'Робочий час перетинається зі зміною', 'Czas pracy nakłada się na zmianę', 'El horario se solapa con el turno', 'Çalışma süresi vardiya ile çakışıyor', 'Ish vaqti smena bilan ustma-ust tushadi'],
  'Измените время начала или окончания.': ['Change the start or end time.', 'Змініть час початку або завершення.', 'Zmień godzinę początku lub końca.', 'Cambia la hora de inicio o fin.', 'Başlangıç veya bitiş saatini değiştirin.', 'Boshlanish yoki tugash vaqtini oʻzgartiring.'],
  'Добавлен тариф': ['Rate added', 'Тариф додано', 'Dodano stawkę', 'Tarifa añadida', 'Tarife eklendi', 'Tarif qoʻshildi'],
  'центов/ч': ['cents/h', 'центів/год', 'centów/godz.', 'céntimos/h', 'sent/sa', 'sent/soat'],
  'Проект создан.': ['Project created.', 'Проєкт створено.', 'Projekt utworzony.', 'Proyecto creado.', 'Proje oluşturuldu.', 'Loyiha yaratildi.'],
  'Учёт оплаты': ['Pay tracking', 'Облік оплати', 'Śledzenie płacy', 'Registro de pago', 'Ücret takibi', 'Toʻlov hisobi'],
  'включён': ['on', 'увімкнено', 'włączone', 'activado', 'açık', 'yoqilgan'],
  'выключен': ['off', 'вимкнено', 'wyłączone', 'desactivado', 'kapalı', 'oʻchirilgan'],
  'Пора сделать check-in': ['Time to check in', 'Час зробити check-in', 'Czas na check-in', 'Hora de hacer check-in', 'Check-in zamanı', 'Check-in vaqti'],
  'Пора подтвердить начало работы': ['Confirm your work start', 'Підтвердьте початок роботи', 'Potwierdź początek pracy', 'Confirma el inicio del trabajo', 'İşe başladığınızı onaylayın', 'Ish boshlanishini tasdiqlang'],
  'Пора сделать check-out': ['Time to check out', 'Час зробити check-out', 'Czas na check-out', 'Hora de hacer check-out', 'Check-out zamanı', 'Check-out vaqti'],
  'Выберите тариф и отметьте начало.': ['Choose a rate and mark the start.', 'Виберіть тариф і позначте початок.', 'Wybierz stawkę i oznacz początek.', 'Elige una tarifa y marca el inicio.', 'Tarifeyi seçin ve başlangıcı işaretleyin.', 'Tarifni tanlang va boshlanishni belgilang.'],
  'Вы на месте?': ['Have you arrived?', 'Ви вже на місці?', 'Jesteś na miejscu?', '¿Has llegado?', 'İş yerine vardınız mı?', 'Ish joyiga yetib keldingizmi?'],
  'Смена ещё не завершена.': ['Your shift is still open.', 'Зміну ще не завершено.', 'Zmiana nadal trwa.', 'El turno sigue abierto.', 'Vardiyanız hâlâ açık.', 'Smena hali yakunlanmagan.'],
  'Конец смены': ['Shift end', 'Кінець зміни', 'Koniec zmiany', 'Fin del turno', 'Vardiya sonu', 'Smena tugashi'],
  'Начало смены': ['Shift start', 'Початок зміни', 'Początek zmiany', 'Inicio del turno', 'Vardiya başlangıcı', 'Smena boshlanishi'],
  'Напоминания о завершении работы': ['Work end reminders', 'Нагадування про завершення роботи', 'Przypomnienia o końcu pracy', 'Recordatorios de fin de trabajo', 'İş bitiş hatırlatıcıları', 'Ish tugashi eslatmalari'],
  'Напоминания о начале работы': ['Work start reminders', 'Нагадування про початок роботи', 'Przypomnienia o początku pracy', 'Recordatorios de inicio de trabajo', 'İş başlangıcı hatırlatıcıları', 'Ish boshlanishi eslatmalari'],
  'Конец': ['End', 'Кінець', 'Koniec', 'Fin', 'Bitiş', 'Tugash'],
  'Учтено, мин': ['Recorded, min', 'Враховано, хв', 'Zapisano, min', 'Registrado, min', 'Kaydedilen, dk', 'Hisoblangan, daq'],
  'Ставка за час': ['Hourly rate', 'Погодинний тариф', 'Stawka godzinowa', 'Tarifa por hora', 'Saatlik ücret', 'Soatlik tarif'],
  'Начислено': ['Earned', 'Нараховано', 'Naliczono', 'Devengado', 'Kazanılan', 'Hisoblangan summa'],
  'Всего часов': ['Total time', 'Усього часу', 'Łączny czas', 'Tiempo total', 'Toplam süre', 'Jami vaqt'],
  'Итого': ['Total', 'Разом', 'Razem', 'Total', 'Toplam', 'Jami'],
};
