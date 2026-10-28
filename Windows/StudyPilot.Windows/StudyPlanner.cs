namespace StudyPilot.Windows;

public static class StudyPlanner
{
    public static DateTime NextAvailableStart(IEnumerable<StudyBlock> blocks, DateTime now, int duration) => FindNextSlot(blocks, now, now.AddDays(14), duration);

    public static int Generate(IList<Assignment> assignments, IList<StudyBlock> blocks, DateTime now)
    {
        var created = 0;
        foreach (var assignment in assignments.Where(x => !x.IsDone).OrderByDescending(PriorityScore).ThenBy(x => x.DueDate))
        {
            var alreadyPlanned = blocks.Where(x => x.AssignmentId == assignment.Id && !x.IsDone && x.End > now).Sum(x => x.DurationMinutes);
            var remaining = Math.Max(0, assignment.EstimatedMinutes - alreadyPlanned);
            while (remaining > 0)
            {
                var duration = Math.Min(45, remaining);
                var start = FindNextSlot(blocks, now, assignment.DueDate.Date.AddDays(1), duration);
                blocks.Add(new StudyBlock { AssignmentId = assignment.Id, Title = assignment.Title, Subject = assignment.Subject, Start = start, DurationMinutes = duration });
                remaining -= duration;
                created++;
            }
        }
        return created;
    }

    public static int RescheduleOverdue(IList<StudyBlock> blocks, DateTime now)
    {
        var moved = 0;
        foreach (var block in blocks.Where(x => !x.IsDone && x.End < now).OrderBy(x => x.Start).ToList())
        {
            block.Start = FindNextSlot(blocks.Where(x => x.Id != block.Id).ToList(), now, now.AddDays(14), block.DurationMinutes);
            moved++;
        }
        return moved;
    }

    private static DateTime FindNextSlot(IEnumerable<StudyBlock> blocks, DateTime now, DateTime deadline, int duration)
    {
        var candidate = RoundToNextHalfHour(now.AddMinutes(15));
        if (candidate.Hour < 16 && candidate.DayOfWeek is not DayOfWeek.Saturday and not DayOfWeek.Sunday) candidate = candidate.Date.AddHours(16);
        if (candidate.Hour < 10 && candidate.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday) candidate = candidate.Date.AddHours(10);
        for (var attempt = 0; attempt < 800; attempt++)
        {
            var dayEndHour = candidate.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday ? 20 : 21;
            if (candidate.AddMinutes(duration).Hour > dayEndHour || candidate.AddMinutes(duration).Date > candidate.Date)
            {
                candidate = candidate.Date.AddDays(1);
                candidate = candidate.AddHours(candidate.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday ? 10 : 16);
                continue;
            }
            var end = candidate.AddMinutes(duration);
            var overlaps = blocks.Any(x => !x.IsDone && candidate < x.End.AddMinutes(10) && end.AddMinutes(10) > x.Start);
            if (!overlaps) return candidate;
            candidate = candidate.AddMinutes(30);
        }
        return deadline > now ? deadline.AddHours(-1) : now.AddHours(1);
    }

    private static DateTime RoundToNextHalfHour(DateTime value)
    {
        var minutes = value.Minute < 30 ? 30 : 60;
        return value.Date.AddHours(value.Hour).AddMinutes(minutes);
    }
    private static int PriorityScore(Assignment assignment) => assignment.Priority switch { "High" => 3, "Low" => 1, _ => 2 };
}
