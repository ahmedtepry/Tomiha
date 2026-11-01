# الناصية (Nasya)

عربية قهوة متنقلة: العميل يطلب من التطبيق وهو في الطريق، ويستلم قهوته جاهزة.

## الأجزاء

| الجزء | الملف | الناتج |
| --- | --- | --- |
| تطبيق العميل (Android) | `lib/main.dart` + `lib/customer.dart` | `nasya.apk` |
| برنامج الكاشير (Windows) | `lib/main_cashier.dart` + `lib/cashier.dart` | `nasya-cashier-windows.zip` (فيه `nasya.exe`) |
| قاعدة البيانات (Supabase، مشروع `nasya`) | `supabase/migrations/` | جداول وRLS ودوال الطلبات والورديات |

كود مشترك في `lib/core.dart` (الألوان، الموديلات، الاتصال بـ Supabase).

## بناء APK وEXE

البناء بيحصل أوتوماتيك على GitHub Actions أول ما تعمل push على `main` (أو من تبويب Actions ثم Run workflow).
الملفات بتطلع في تبويب **Releases** باسم `Build N`:

- `nasya.apk`: ثبّته على أندرويد (فعّل التثبيت من مصدر غير معروف).
- `nasya-cashier-windows.zip`: فكّ الضغط وشغّل `nasya.exe` من جوه الفولدر (متنقلوش لوحده، محتاج الملفات اللي جنبه).

بناء محلي (محتاج Flutter):

```
flutter create --platforms=android,windows --project-name nasya .
flutter build apk --release -t lib/main.dart
flutter build windows --release -t lib/main_cashier.dart
```

بعد `flutter create` ضيف إذن `INTERNET` في `android/app/src/main/AndroidManifest.xml`.

## إعداد لمرة واحدة

1. **Supabase**: Authentication ثم Sign In / Providers ثم Email، وقفّل **Confirm email**، عشان العملاء يدخلوا من غير إيميل تأكيد.
2. **أول حساب موظف**: سجّل حساب من تطبيق العميل، وبعدين شغّل في SQL Editor:

   ```sql
   update public.profiles set role = 'manager'
   where id = (select id from auth.users where email = 'EMAIL_HERE');
   ```

   وبعدها تدخل بيه على برنامج الكاشير. الأدوار: `customer` و`cashier` و`manager`.

## ملاحظات

- الدفع بالمحفظة بيتسجّل ويتأكد يدويًا من الكاشير، ومفيش ربط ببوابة دفع لسه.
- الأسعار بتتحسب في السيرفر (`place_order`)، فالعميل مايقدرش يغيّرها.
- أسعار المنيو في المخطط تقديرية، وبتتعدل من جدول `drink_prices`.
- الأرقام المالية في `docs/nasya_menu.xlsx`.
