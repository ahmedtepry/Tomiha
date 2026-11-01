# BONNAYA (بنايه)

عربية قهوة متنقلة: العميل يطلب من التطبيق وهو في الطريق، ويستلم قهوته جاهزة.

## الأجزاء

| الجزء | الملف | الناتج |
| --- | --- | --- |
| تطبيق العميل (Android) | `lib/main.dart` + `lib/customer.dart` | `bonnaya.apk` |
| برنامج الكاشير (Windows) | `lib/main_cashier.dart` + `lib/cashier.dart` | `bonnaya-cashier-windows.zip` (فيه `bonnaya.exe`) |
| قاعدة البيانات (Supabase، مشروع `nasya`) | `supabase/migrations/` | جداول وRLS ودوال الطلبات والورديات |

كود مشترك في `lib/core.dart` (الألوان، الموديلات، الاتصال بـ Supabase).

## بناء APK وEXE

البناء بيحصل أوتوماتيك على GitHub Actions أول ما تعمل push على `main` (أو من تبويب Actions ثم Run workflow).
الملفات بتطلع في تبويب **Releases** باسم `Build N`:

- `bonnaya.apk`: ثبّته على أندرويد (فعّل التثبيت من مصدر غير معروف).
- `bonnaya-cashier-windows.zip`: فكّ الضغط وشغّل `bonnaya.exe` من جوه الفولدر (متنقلوش لوحده، محتاج الملفات اللي جنبه).

بناء محلي (محتاج Flutter):

```
flutter create --platforms=android,windows --project-name bonnaya .
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

## شاشة الترحيب والمظهر

- أول ما العميل يفتح الأبلكيشن: كوباية بتتملي لوحدها وبخار ومقولة عن القهوة، وبعدها المنيو.
- المالك (دور `manager`) من برنامج الكاشير: زرار الباليتة فوق ← شاشة الترحيب، يختار الكوباية (5 اشكال) ويعدّل المقولات ويعاين ويحفظ.
- الإعدادات في جدول `app_settings` (قراءة للجميع، كتابة للمالك فقط).
- العميل يتصفح المنيو من غير تسجيل، والدخول بيتطلب لما يضغط تأكيد الطلب.
