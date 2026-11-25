# WinKit

Минималистичный GUI-инсталлятор и менеджер обновлений для Windows 10/11 на базе WinGet.

[English](README.md) | [Русский](README-RU.md)

![Демо WinKit](winkit-preview.gif)

## Быстрый старт

Запуск через PowerShell:

```powershell
irm https://raw.githubusercontent.com/Refyrd/WinKit/main/install.ps1 | iex
```

Или локально из репозитория:

```powershell
git clone https://github.com/Refyrd/WinKit.git
cd WinKit
powershell -ExecutionPolicy Bypass -File winkit.ps1
```

## Возможности

- Каталог из 42 приложений в 7 категориях (`src/config/Apps.ps1`)
- Онлайн-поиск по репозиторию WinGet прямо из строки поиска (`Enter`)
- Фоновое сканирование установленных программ и доступных обновлений
- Обновление всех устаревших программ одной кнопкой `Upgrade All`
- Сохранение и загрузка пресетов в формате WinGet JSON (`.json`) или `.txt`
- Последовательная пакетная установка с живым логом, экспортом отчёта и отменой
- Автоповышение прав (UAC) и запуск в контексте пользователя для приложений вроде Discord, Telegram, Spotify, Roblox, Obsidian, Notion
- Эффект Mica в Windows 11 и синхронизация со светлой/тёмной темой системы

## Требования

- Windows 10 (1709+) или Windows 11
- WinGet (встроен в Windows 11; при отсутствии автоматически ставится через `Microsoft.WinGet.Client`)

## Добавление своих программ

Отредактируйте [`src/config/Apps.ps1`](src/config/Apps.ps1) и добавьте записи с полями `Name`, `Id` и `Cat` в массив `$global:apps`.

## Лицензия

[Apache 2.0](LICENSE) (см. [NOTICE](NOTICE))
