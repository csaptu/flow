# Flow Projects - Detailed Plan

## Overview

Flow Projects is the **powerful project management app** for complex, multi-phase work. It handles Waterfall dependencies, unlimited task depth, Gantt charts, team collaboration, and AI-powered project planning.

**Core Principles:**
- When a task in Flow Tasks becomes too complex, it graduates here
- Full Work Breakdown Structure (WBS) with dependencies
- Tasks promoted from Flow Tasks are COPIES (not moves)

**Data Architecture:**
- All project data stored in `projects_db` (owned by projects-service)
- WBS nodes use `wbs_nodes` table (NOT the `tasks` table from tasks_db)
- `source_task_id` field tracks if a WBS node was promoted from a personal task
- Projects-service exposes API for "Assigned to Me" queries from tasks-service

**Cross-Domain APIs:**
```
# Flow Tasks app calls this to show "Assigned to Me" tab
GET /api/v1/users/{user_id}/assigned-tasks
→ Returns wbs_nodes where assignee_id = user_id

# Tasks-service calls this during promotion
POST /api/v1/internal/wbs-nodes
→ Creates a new WBS node from promoted task data
```

---

## 0. Feature → Method Mapping (Complete Reference)

### 0.1 Projects CRUD

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| List user's projects | `projectListProvider` | `GET /projects` | `ProjectService.ListByUser()` |
| Get project details | `projectDetailProvider(id)` | `GET /projects/:id` | `ProjectService.GetByID()` |
| Create project | `ProjectListNotifier.create()` | `POST /projects` | `ProjectService.Create()` |
| Update project | `ProjectDetailNotifier.update()` | `PUT /projects/:id` | `ProjectService.Update()` |
| Delete project | `ProjectDetailNotifier.delete()` | `DELETE /projects/:id` | `ProjectService.Delete()` |
| Get project stats | `projectStatsProvider(id)` | `GET /projects/:id/stats` | `ProjectService.GetStats()` |

```dart
// Frontend: lib/features/projects/providers/project_list_provider.dart
@riverpod
class ProjectListNotifier extends _$ProjectListNotifier {
  @override
  Future<List<Project>> build() async {
    return ref.watch(projectRepositoryProvider).listProjects();
  }

  Future<Project> create(ProjectCreate request) async {
    final project = await ref.read(projectRepositoryProvider).createProject(request);
    ref.invalidateSelf();
    return project;
  }
}
```

```go
// Backend: projects/handler.go
func (h *Handler) RegisterRoutes(app *fiber.App) {
    projects := app.Group("/api/v1/projects")
    projects.Get("/", h.ListProjects)
    projects.Post("/", h.CreateProject)
    projects.Get("/:id", h.GetProject)
    projects.Put("/:id", h.UpdateProject)
    projects.Delete("/:id", h.DeleteProject)
    projects.Get("/:id/stats", h.GetProjectStats)
}
```

---

### 0.2 WBS Nodes (Work Breakdown Structure)

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| Get WBS tree | `wbsTreeProvider(projectId)` | `GET /projects/:id/wbs` | `WBSService.GetTree()` |
| Create node | `WBSNotifier.createNode()` | `POST /projects/:id/wbs` | `WBSService.CreateNode()` |
| Update node | `WBSNotifier.updateNode()` | `PUT /wbs/:nodeId` | `WBSService.UpdateNode()` |
| Delete node | `WBSNotifier.deleteNode()` | `DELETE /wbs/:nodeId` | `WBSService.DeleteNode()` |
| Move node | `WBSNotifier.moveNode()` | `PUT /wbs/:nodeId/move` | `WBSService.MoveNode()` |
| Reorder nodes | `WBSNotifier.reorder()` | `PUT /wbs/:nodeId/reorder` | `WBSService.Reorder()` |
| **Create from promotion** | N/A (called by tasks-service) | `POST /internal/wbs-nodes` | `WBSService.CreateFromPromotion()` |

```dart
// Frontend: lib/features/wbs/providers/wbs_provider.dart
@riverpod
class WBSNotifier extends _$WBSNotifier {
  @override
  Future<List<WbsNode>> build(String projectId) async {
    return ref.watch(wbsRepositoryProvider).getTree(projectId);
  }

  Future<WbsNode> createNode(WbsNodeCreate request) async {
    final node = await ref.read(wbsRepositoryProvider).createNode(request);
    ref.invalidateSelf();
    return node;
  }

  Future<void> moveNode(String nodeId, String? newParentId) async {
    await ref.read(wbsRepositoryProvider).moveNode(nodeId, newParentId);
    ref.invalidateSelf();
  }
}
```

```go
// Backend: projects/wbs_handler.go
func (h *WBSHandler) RegisterRoutes(app *fiber.App) {
    wbs := app.Group("/api/v1")
    wbs.Get("/projects/:projectId/wbs", h.GetTree)
    wbs.Post("/projects/:projectId/wbs", h.CreateNode)
    wbs.Put("/wbs/:nodeId", h.UpdateNode)
    wbs.Delete("/wbs/:nodeId", h.DeleteNode)
    wbs.Put("/wbs/:nodeId/move", h.MoveNode)
    wbs.Put("/wbs/:nodeId/reorder", h.Reorder)

    // Internal API (called by tasks-service during promotion)
    internal := app.Group("/api/v1/internal")
    internal.Post("/wbs-nodes", h.CreateFromPromotion)
}

// Backend: projects/wbs_service.go
func (s *WBSService) CreateFromPromotion(ctx context.Context, req PromotionRequest) (*WBSNode, error) {
    node := &WBSNode{
        ID:           uuid.New(),
        ProjectID:    req.ProjectID,
        ParentID:     req.ParentNodeID,
        Title:        req.Title,
        Description:  req.Description,
        AISummary:    req.AISummary,
        AISteps:      req.AISteps,
        Status:       req.Status,
        Priority:     req.Priority,
        SourceUserID: &req.UserID,
        SourceTaskID: &req.TaskID,
        PromotedAt:   timePtr(time.Now()),
    }
    return s.repo.Create(ctx, node)
}
```

---

### 0.3 Dependencies

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| List dependencies | `dependenciesProvider(projectId)` | `GET /projects/:id/dependencies` | `DependencyService.List()` |
| Create dependency | `DependencyNotifier.create()` | `POST /dependencies` | `DependencyService.Create()` |
| Update dependency | `DependencyNotifier.update()` | `PUT /dependencies/:id` | `DependencyService.Update()` |
| Delete dependency | `DependencyNotifier.delete()` | `DELETE /dependencies/:id` | `DependencyService.Delete()` |
| Get critical path | `criticalPathProvider(projectId)` | `GET /projects/:id/critical-path` | `WaterfallService.CriticalPath()` |
| Validate (no cycles) | Auto on create | Validated in Create | `DependencyService.ValidateNoCycles()` |

```dart
// Frontend: lib/features/dependencies/providers/dependency_provider.dart
@riverpod
class DependencyNotifier extends _$DependencyNotifier {
  @override
  Future<List<TaskDependency>> build(String projectId) async {
    return ref.watch(dependencyRepositoryProvider).list(projectId);
  }

  Future<TaskDependency> create({
    required String predecessorId,
    required String successorId,
    DependencyType type = DependencyType.finishToStart,
    int lagDays = 0,
  }) async {
    final dep = await ref.read(dependencyRepositoryProvider).create(
      DependencyCreate(
        predecessorId: predecessorId,
        successorId: successorId,
        type: type,
        lagDays: lagDays,
      ),
    );
    ref.invalidateSelf();
    // Also invalidate Gantt and critical path
    ref.invalidate(ganttDataProvider);
    ref.invalidate(criticalPathProvider);
    return dep;
  }
}
```

```go
// Backend: projects/dependency_service.go
func (s *DependencyService) Create(ctx context.Context, req DependencyCreate) (*Dependency, error) {
    // 1. Validate no cycles
    if err := s.validateNoCycles(ctx, req.PredecessorID, req.SuccessorID); err != nil {
        return nil, ErrCyclicDependency
    }

    // 2. Validate both nodes exist and in same project
    pred, err := s.wbsRepo.GetByID(ctx, req.PredecessorID)
    succ, err := s.wbsRepo.GetByID(ctx, req.SuccessorID)
    if pred.ProjectID != succ.ProjectID {
        return nil, ErrCrossProjectDependency
    }

    // 3. Create dependency
    dep := &Dependency{
        ID:            uuid.New(),
        PredecessorID: req.PredecessorID,
        SuccessorID:   req.SuccessorID,
        Type:          req.Type,
        LagDays:       req.LagDays,
    }
    return s.repo.Create(ctx, dep)
}
```

---

### 0.4 Gantt Chart

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| Get Gantt data | `ganttDataProvider(projectId)` | `GET /projects/:id/gantt` | `GanttService.GetData()` |
| Update bar dates | `GanttNotifier.updateDates()` | `PUT /wbs/:nodeId` (dates) | `WBSService.UpdateNode()` |
| Auto-schedule | `GanttNotifier.autoSchedule()` | `POST /projects/:id/auto-schedule` | `WaterfallService.AutoSchedule()` |
| Zoom in/out | Local state only | N/A | N/A |
| Scroll to today | Local state only | N/A | N/A |

#### Responsive Gantt Strategy

Traditional Gantt charts don't fit small screens. Use adaptive views:

```
┌─────────────────────────────────────────────────────────────────┐
│                    RESPONSIVE STRATEGY                           │
└─────────────────────────────────────────────────────────────────┘

Screen Width        Default View              Gantt Access
─────────────────────────────────────────────────────────────────
< 600px (phone)     Timeline List             Bottom sheet toggle
600-900px (tablet)  Split (list + mini Gantt) Always visible
> 900px (desktop)   Full Gantt Chart          Default
```

**Mobile: Timeline List View (Default)**
```
┌─────────────────────────────────────┐
│ Project Alpha       [📊 Gantt]     │  ← Toggle button
├─────────────────────────────────────┤
│                                     │
│ 📋 1.0 Planning          Jan 15-20  │
│ ████████░░░░ 70%                    │
│                                     │
│ 📋 1.1 Research          Jan 15-17  │
│ ████████████ Done ✓                 │
│                                     │
│ 📋 1.2 Design            Jan 18-22  │
│ ████░░░░░░░░ 40%     ← Depends: 1.1 │
│                                     │
└─────────────────────────────────────┘
```

**Mobile: Full Gantt (Bottom Sheet)**
```
┌─────────────────────────────────────┐
│ ──────  Drag to expand              │
├──────────────┬──────────────────────┤
│ Task         │ Jan    Feb    Mar    │ ← horizontal scroll
├──────────────┼──────────────────────┤
│ 1.0 Planning │ ████████             │
│ 1.1 Research │ ████                 │
│ 1.2 Design   │    ██████████        │
└──────────────┴──────────────────────┘
        ↑ fixed     ↑ scrollable

Gestures: Pinch to zoom, swipe to pan
```

**Tablet: Split View**
```
┌────────────────────┬────────────────────────────────────────────┐
│ Tasks              │ Mini Gantt                                  │
├────────────────────┼────────────────────────────────────────────┤
│ ▼ 1.0 Planning     │      Jan         Feb         Mar           │
│   • 1.1 Research   │ ─────────────────────────────────────────  │
│   • 1.2 Design     │ ████████                                   │
│ ▼ 2.0 Execution    │ ████                                       │
│   • 2.1 Build      │     ████████                               │
│   • 2.2 Test       │              ██████████                    │
│                    │                    ████████████            │
└────────────────────┴────────────────────────────────────────────┘
      flex: 1                    flex: 2
```

```dart
// Frontend: lib/features/gantt/presentation/screens/gantt_screen.dart

class GanttScreen extends ConsumerWidget {
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ganttData = ref.watch(ganttDataProvider(projectId));

    return ganttData.when(
      data: (data) => _buildResponsiveView(context, ref, data, screenWidth),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
    );
  }

  Widget _buildResponsiveView(
    BuildContext context,
    WidgetRef ref,
    GanttData data,
    double screenWidth,
  ) {
    // Mobile: Timeline list with toggle
    if (screenWidth < 600) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Timeline'),
          actions: [
            IconButton(
              icon: Icon(Icons.bar_chart),
              tooltip: 'Show Gantt',
              onPressed: () => _showGanttBottomSheet(context, data),
            ),
          ],
        ),
        body: TimelineListView(data: data),
      );
    }

    // Tablet: Split view
    if (screenWidth < 900) {
      return Row(
        children: [
          Expanded(flex: 1, child: TaskListPanel(data: data)),
          VerticalDivider(width: 1),
          Expanded(flex: 2, child: MiniGanttChart(data: data)),
        ],
      );
    }

    // Desktop: Full Gantt
    return FullGanttChart(data: data);
  }

  void _showGanttBottomSheet(BuildContext context, GanttData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Zoom controls
              GanttZoomControls(),
              // Scrollable Gantt
              Expanded(
                child: HorizontalScrollGantt(
                  data: data,
                  scrollController: controller,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
// Frontend: lib/features/gantt/presentation/widgets/timeline_list_view.dart

class TimelineListView extends StatelessWidget {
  final GanttData data;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: data.nodes.length,
      itemBuilder: (context, index) {
        final node = data.nodes[index];
        return TimelineListTile(
          node: node,
          dependencies: data.dependencies
              .where((d) => d.successorId == node.id)
              .toList(),
        );
      },
    );
  }
}

class TimelineListTile extends StatelessWidget {
  final WbsNode node;
  final List<TaskDependency> dependencies;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WBS code + Title
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    node.wbsCode,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.title,
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),

            SizedBox(height: 8),

            // Date range
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  '${_formatDate(node.startDate)} - ${_formatDate(node.endDate)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                Spacer(),
                if (node.estimatedHours != null)
                  Text(
                    '${node.estimatedHours}h',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),

            SizedBox(height: 8),

            // Progress bar (mini Gantt bar)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: node.progressPercent / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(_statusColor(node.status)),
                minHeight: 8,
              ),
            ),

            SizedBox(height: 8),

            // Status + Assignee + Dependencies
            Row(
              children: [
                _StatusChip(status: node.status),
                SizedBox(width: 8),
                if (node.assigneeId != null) ...[
                  _AssigneeChip(userId: node.assigneeId!),
                  SizedBox(width: 8),
                ],
                Spacer(),
                if (dependencies.isNotEmpty)
                  _DependencyChip(count: dependencies.length),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.completed: return Colors.green;
      case TaskStatus.inProgress: return Colors.blue;
      case TaskStatus.pending: return Colors.grey;
      case TaskStatus.blocked: return Colors.red;
      default: return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('MMM d').format(date);
  }
}
```

```dart
// Frontend: lib/features/gantt/presentation/widgets/horizontal_scroll_gantt.dart

class HorizontalScrollGantt extends ConsumerStatefulWidget {
  final GanttData data;
  final ScrollController? scrollController;

  @override
  ConsumerState<HorizontalScrollGantt> createState() => _HorizontalScrollGanttState();
}

class _HorizontalScrollGanttState extends ConsumerState<HorizontalScrollGantt> {
  late TransformationController _transformController;
  double _currentScale = 1.0;

  // Zoom levels: day, week, month
  static const _zoomLevels = [
    ZoomLevel(name: 'Day', dayWidth: 40),
    ZoomLevel(name: 'Week', dayWidth: 20),
    ZoomLevel(name: 'Month', dayWidth: 8),
  ];
  int _currentZoomIndex = 1; // Default: week

  @override
  Widget build(BuildContext context) {
    final timeScale = TimeScale(
      startDate: widget.data.projectStartDate,
      endDate: widget.data.projectEndDate,
      dayWidth: _zoomLevels[_currentZoomIndex].dayWidth,
    );

    return Column(
      children: [
        // Zoom controls
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_zoomLevels.length, (i) {
              final level = _zoomLevels[i];
              final isSelected = i == _currentZoomIndex;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(level.name),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _currentZoomIndex = i),
                ),
              );
            }),
          ),
        ),

        // Gantt chart
        Expanded(
          child: Row(
            children: [
              // Fixed task column
              SizedBox(
                width: 120,
                child: ListView.builder(
                  controller: widget.scrollController,
                  itemCount: widget.data.nodes.length,
                  itemBuilder: (_, i) => _TaskNameCell(
                    node: widget.data.nodes[i],
                    height: 40,
                  ),
                ),
              ),

              VerticalDivider(width: 1),

              // Scrollable timeline
              Expanded(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  scaleEnabled: true,
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: CustomPaint(
                    size: Size(timeScale.totalWidth, widget.data.nodes.length * 40.0),
                    painter: GanttChartPainter(
                      nodes: widget.data.nodes,
                      dependencies: widget.data.dependencies,
                      timeScale: timeScale,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

```dart
// Frontend: lib/features/gantt/providers/gantt_provider.dart
@riverpod
Future<GanttData> ganttData(GanttDataRef ref, String projectId) async {
  final nodes = await ref.watch(wbsRepositoryProvider).getTree(projectId);
  final deps = await ref.watch(dependencyRepositoryProvider).list(projectId);
  final project = await ref.watch(projectRepositoryProvider).getById(projectId);

  return GanttData(
    nodes: nodes.flatten(), // Flatten tree for Gantt bars
    dependencies: deps,
    projectStartDate: project.startDate ?? DateTime.now(),
    projectEndDate: project.targetEndDate ?? DateTime.now().add(Duration(days: 90)),
  );
}

@riverpod
class GanttNotifier extends _$GanttNotifier {
  Future<void> updateNodeDates(String nodeId, DateTime start, DateTime end) async {
    await ref.read(wbsRepositoryProvider).updateNode(
      nodeId,
      WbsNodeUpdate(startDate: start, endDate: end),
    );
    ref.invalidate(ganttDataProvider);
    ref.invalidate(criticalPathProvider);
  }

  Future<void> autoSchedule(String projectId) async {
    await ref.read(projectRepositoryProvider).autoSchedule(projectId);
    ref.invalidate(ganttDataProvider);
    ref.invalidate(wbsTreeProvider(projectId));
  }
}
```

```go
// Backend: projects/gantt_handler.go
func (h *GanttHandler) GetGanttData(c *fiber.Ctx) error {
    projectID := c.Params("id")

    nodes, _ := h.wbsService.GetFlatList(c.Context(), projectID)
    deps, _ := h.depService.List(c.Context(), projectID)
    project, _ := h.projectService.GetByID(c.Context(), projectID)

    return c.JSON(GanttDataResponse{
        Nodes:        nodes,
        Dependencies: deps,
        StartDate:    project.StartDate,
        EndDate:      project.TargetEndDate,
    })
}

// Backend: projects/waterfall/scheduler.go
func (s *WaterfallService) AutoSchedule(ctx context.Context, projectID uuid.UUID) error {
    nodes, _ := s.wbsRepo.GetFlatList(ctx, projectID)
    deps, _ := s.depRepo.List(ctx, projectID)

    // Topological sort
    sorted := s.topologicalSort(nodes, deps)

    // Forward pass: calculate early start/finish
    for _, node := range sorted {
        earlyStart := s.calculateEarlyStart(node, deps)
        earlyFinish := earlyStart.Add(time.Duration(node.EstimatedHours) * time.Hour)

        s.wbsRepo.Update(ctx, node.ID, WBSUpdate{
            StartDate: &earlyStart,
            EndDate:   &earlyFinish,
        })
    }

    return nil
}
```

---

### 0.5 Team & Assignments

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| List team members | `teamMembersProvider(projectId)` | `GET /projects/:id/members` | `TeamService.ListMembers()` |
| Add member | `TeamNotifier.addMember()` | `POST /projects/:id/members` | `TeamService.AddMember()` |
| Remove member | `TeamNotifier.removeMember()` | `DELETE /projects/:id/members/:userId` | `TeamService.RemoveMember()` |
| Update role | `TeamNotifier.updateRole()` | `PUT /projects/:id/members/:userId` | `TeamService.UpdateRole()` |
| Assign task | `WBSNotifier.assignNode()` | `PUT /wbs/:nodeId` (assigneeId) | `WBSService.UpdateNode()` |
| Get workload | `workloadProvider(projectId)` | `GET /projects/:id/workload` | `TeamService.GetWorkload()` |
| **Get assigned tasks** (for Flow Tasks) | N/A | `GET /users/:userId/assigned-tasks` | `TeamService.GetAssignedTasks()` |

```dart
// Frontend: lib/features/team/providers/team_provider.dart
@riverpod
class TeamNotifier extends _$TeamNotifier {
  @override
  Future<List<TeamMember>> build(String projectId) async {
    return ref.watch(teamRepositoryProvider).listMembers(projectId);
  }

  Future<void> addMember(String userId, MemberRole role) async {
    await ref.read(teamRepositoryProvider).addMember(
      projectId: state.requireValue.first.projectId,
      userId: userId,
      role: role,
    );
    ref.invalidateSelf();
  }

  Future<void> assignTask(String nodeId, String? assigneeId) async {
    await ref.read(wbsRepositoryProvider).updateNode(
      nodeId,
      WbsNodeUpdate(assigneeId: assigneeId),
    );
    ref.invalidate(workloadProvider);
  }
}

@riverpod
Future<Map<String, WorkloadData>> workload(WorkloadRef ref, String projectId) async {
  return ref.watch(teamRepositoryProvider).getWorkload(projectId);
}
```

```go
// Backend: projects/team_handler.go
func (h *TeamHandler) RegisterRoutes(app *fiber.App) {
    team := app.Group("/api/v1/projects/:projectId/members")
    team.Get("/", h.ListMembers)
    team.Post("/", h.AddMember)
    team.Put("/:userId", h.UpdateRole)
    team.Delete("/:userId", h.RemoveMember)

    // Workload
    app.Get("/api/v1/projects/:projectId/workload", h.GetWorkload)

    // Cross-domain API: Called by Flow Tasks for "Assigned to Me"
    app.Get("/api/v1/users/:userId/assigned-tasks", h.GetAssignedTasks)
}

// Backend: projects/team_service.go
func (s *TeamService) GetAssignedTasks(ctx context.Context, userID uuid.UUID) ([]WBSNode, error) {
    return s.wbsRepo.FindByAssignee(ctx, userID)
}

func (s *TeamService) GetWorkload(ctx context.Context, projectID uuid.UUID) (map[uuid.UUID]WorkloadData, error) {
    members, _ := s.repo.ListMembers(ctx, projectID)
    result := make(map[uuid.UUID]WorkloadData)

    for _, m := range members {
        nodes, _ := s.wbsRepo.FindByAssignee(ctx, m.UserID)
        totalHours := 0
        for _, n := range nodes {
            if n.EstimatedHours != nil {
                totalHours += *n.EstimatedHours
            }
        }
        result[m.UserID] = WorkloadData{
            TaskCount:  len(nodes),
            TotalHours: totalHours,
        }
    }
    return result, nil
}
```

---

### 0.6 AI Features

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| Estimate task hours | `AINotifier.estimateHours()` | `POST /wbs/:nodeId/ai/estimate` | `AIService.EstimateHours()` |
| Analyze risks | `projectRisksProvider(projectId)` | `GET /projects/:id/ai/risks` | `AIService.AnalyzeRisks()` |
| Suggest schedule | `AINotifier.suggestSchedule()` | `POST /projects/:id/ai/suggest-schedule` | `AIService.SuggestSchedule()` |
| Decompose node | `AINotifier.decompose()` | `POST /wbs/:nodeId/ai/decompose` | `AIService.DecomposeNode()` |
| Generate WBS | `AINotifier.generateWBS()` | `POST /projects/:id/ai/generate-wbs` | `AIService.GenerateWBS()` |

```dart
// Frontend: lib/features/ai/providers/ai_project_provider.dart
@riverpod
class AIProjectNotifier extends _$AIProjectNotifier {
  Future<int> estimateHours(String nodeId) async {
    final estimate = await ref.read(aiRepositoryProvider).estimateHours(nodeId);
    // Auto-update the node with estimate
    await ref.read(wbsRepositoryProvider).updateNode(
      nodeId,
      WbsNodeUpdate(estimatedHours: estimate),
    );
    ref.invalidate(wbsTreeProvider);
    return estimate;
  }

  Future<List<WbsNode>> generateWBS(String projectId, String description) async {
    final nodes = await ref.read(aiRepositoryProvider).generateWBS(
      projectId,
      description,
    );
    ref.invalidate(wbsTreeProvider(projectId));
    return nodes;
  }

  Future<List<RiskItem>> analyzeRisks(String projectId) async {
    return ref.read(aiRepositoryProvider).analyzeRisks(projectId);
  }
}

@riverpod
Future<List<RiskItem>> projectRisks(ProjectRisksRef ref, String projectId) async {
  return ref.watch(aiRepositoryProvider).analyzeRisks(projectId);
}
```

```go
// Backend: projects/ai_handler.go
func (h *AIHandler) RegisterRoutes(app *fiber.App) {
    ai := app.Group("/api/v1")
    ai.Post("/wbs/:nodeId/ai/estimate", h.EstimateHours)
    ai.Post("/wbs/:nodeId/ai/decompose", h.DecomposeNode)
    ai.Get("/projects/:id/ai/risks", h.AnalyzeRisks)
    ai.Post("/projects/:id/ai/suggest-schedule", h.SuggestSchedule)
    ai.Post("/projects/:id/ai/generate-wbs", h.GenerateWBS)
}

// Backend: projects/ai_service.go (calls shared/ai via HTTP or direct import)
func (s *AIService) EstimateHours(ctx context.Context, nodeID uuid.UUID) (int, error) {
    node, _ := s.wbsRepo.GetByID(ctx, nodeID)

    prompt := fmt.Sprintf(`
        Estimate hours for this task:
        Title: %s
        Description: %s
        Complexity: %d/10

        Return only a number (hours).
    `, node.Title, node.Description, node.Complexity)

    response, _ := s.llmClient.Complete(ctx, prompt)
    hours, _ := strconv.Atoi(strings.TrimSpace(response))
    return hours, nil
}

func (s *AIService) GenerateWBS(ctx context.Context, projectID uuid.UUID, desc string) ([]WBSNode, error) {
    prompt := fmt.Sprintf(`
        Generate a Work Breakdown Structure for:
        %s

        Return as JSON array: [{"title": "...", "children": [...]}]
    `, desc)

    response, _ := s.llmClient.Complete(ctx, prompt)
    var wbs []WBSNodeCreate
    json.Unmarshal([]byte(response), &wbs)

    // Create nodes in DB
    return s.createWBSFromAI(ctx, projectID, wbs)
}
```

---

### 0.7 Kanban View

| Feature | Frontend (Flutter) | Backend (Go) API | Backend Service |
|---------|-------------------|------------------|-----------------|
| Get Kanban data | `kanbanDataProvider(projectId)` | `GET /projects/:id/kanban` | `KanbanService.GetData()` |
| Move card | `KanbanNotifier.moveCard()` | `PUT /wbs/:nodeId` (status) | `WBSService.UpdateNode()` |
| Reorder in column | `KanbanNotifier.reorder()` | `PUT /wbs/:nodeId/reorder` | `WBSService.Reorder()` |

```dart
// Frontend: lib/features/kanban/providers/kanban_provider.dart
@riverpod
Future<KanbanData> kanbanData(KanbanDataRef ref, String projectId) async {
  final nodes = await ref.watch(wbsRepositoryProvider).getFlatList(projectId);

  return KanbanData(
    columns: [
      KanbanColumn(id: 'pending', title: 'To Do',
        cards: nodes.where((n) => n.status == TaskStatus.pending).toList()),
      KanbanColumn(id: 'in_progress', title: 'In Progress',
        cards: nodes.where((n) => n.status == TaskStatus.inProgress).toList()),
      KanbanColumn(id: 'completed', title: 'Done',
        cards: nodes.where((n) => n.status == TaskStatus.completed).toList()),
    ],
  );
}

@riverpod
class KanbanNotifier extends _$KanbanNotifier {
  Future<void> moveCard(String nodeId, String newStatus) async {
    await ref.read(wbsRepositoryProvider).updateNode(
      nodeId,
      WbsNodeUpdate(status: TaskStatus.values.byName(newStatus)),
    );
    ref.invalidate(kanbanDataProvider);
    ref.invalidate(wbsTreeProvider);
  }
}
```

---

### 0.8 Complete API Endpoint Summary

```go
// Backend: projects/routes.go

func RegisterRoutes(app *fiber.App, h *Handlers) {
    v1 := app.Group("/api/v1")

    // ═══ PROJECTS ═══
    v1.Get("/projects", h.Project.List)
    v1.Post("/projects", h.Project.Create)
    v1.Get("/projects/:id", h.Project.Get)
    v1.Put("/projects/:id", h.Project.Update)
    v1.Delete("/projects/:id", h.Project.Delete)
    v1.Get("/projects/:id/stats", h.Project.GetStats)

    // ═══ WBS NODES ═══
    v1.Get("/projects/:id/wbs", h.WBS.GetTree)
    v1.Post("/projects/:id/wbs", h.WBS.CreateNode)
    v1.Get("/projects/:id/wbs/flat", h.WBS.GetFlatList)
    v1.Put("/wbs/:nodeId", h.WBS.UpdateNode)
    v1.Delete("/wbs/:nodeId", h.WBS.DeleteNode)
    v1.Put("/wbs/:nodeId/move", h.WBS.MoveNode)
    v1.Put("/wbs/:nodeId/reorder", h.WBS.Reorder)

    // ═══ DEPENDENCIES ═══
    v1.Get("/projects/:id/dependencies", h.Dependency.List)
    v1.Post("/dependencies", h.Dependency.Create)
    v1.Put("/dependencies/:id", h.Dependency.Update)
    v1.Delete("/dependencies/:id", h.Dependency.Delete)

    // ═══ GANTT & SCHEDULING ═══
    v1.Get("/projects/:id/gantt", h.Gantt.GetData)
    v1.Get("/projects/:id/critical-path", h.Gantt.GetCriticalPath)
    v1.Post("/projects/:id/auto-schedule", h.Gantt.AutoSchedule)

    // ═══ KANBAN ═══
    v1.Get("/projects/:id/kanban", h.Kanban.GetData)

    // ═══ TEAM ═══
    v1.Get("/projects/:id/members", h.Team.ListMembers)
    v1.Post("/projects/:id/members", h.Team.AddMember)
    v1.Put("/projects/:id/members/:userId", h.Team.UpdateRole)
    v1.Delete("/projects/:id/members/:userId", h.Team.RemoveMember)
    v1.Get("/projects/:id/workload", h.Team.GetWorkload)

    // ═══ AI ═══
    v1.Post("/wbs/:nodeId/ai/estimate", h.AI.EstimateHours)
    v1.Post("/wbs/:nodeId/ai/decompose", h.AI.DecomposeNode)
    v1.Get("/projects/:id/ai/risks", h.AI.AnalyzeRisks)
    v1.Post("/projects/:id/ai/suggest-schedule", h.AI.SuggestSchedule)
    v1.Post("/projects/:id/ai/generate-wbs", h.AI.GenerateWBS)

    // ═══ CROSS-DOMAIN APIs ═══
    // Called by Flow Tasks for "Assigned to Me" tab
    v1.Get("/users/:userId/assigned-tasks", h.Team.GetAssignedTasks)

    // Called by tasks-service during promotion
    internal := app.Group("/api/v1/internal")
    internal.Post("/wbs-nodes", h.WBS.CreateFromPromotion)
}
```

---

### 0.9 Frontend Provider Summary

```dart
// lib/core/providers/providers.dart

// ═══ PROJECTS ═══
@riverpod projectList(ref)              // List<Project>
@riverpod projectDetail(ref, id)        // Project
@riverpod projectStats(ref, id)         // ProjectStats

// ═══ WBS ═══
@riverpod wbsTree(ref, projectId)       // List<WbsNode> (tree)
@riverpod wbsFlatList(ref, projectId)   // List<WbsNode> (flat)
@riverpod wbsNode(ref, nodeId)          // WbsNode

// ═══ DEPENDENCIES ═══
@riverpod dependencies(ref, projectId)  // List<TaskDependency>
@riverpod criticalPath(ref, projectId)  // List<String> (node IDs)

// ═══ GANTT ═══
@riverpod ganttData(ref, projectId)     // GanttData

// ═══ KANBAN ═══
@riverpod kanbanData(ref, projectId)    // KanbanData

// ═══ TEAM ═══
@riverpod teamMembers(ref, projectId)   // List<TeamMember>
@riverpod workload(ref, projectId)      // Map<String, WorkloadData>

// ═══ AI ═══
@riverpod projectRisks(ref, projectId)  // List<RiskItem>
```

---

## 1. Key Differences from Flow Tasks

| Aspect | Flow Tasks | Flow Projects |
|--------|------------|---------------|
| Task Depth | 2 layers max | Unlimited |
| Dependencies | None | Full (FS, SS, FF, SF) |
| Time View | Due dates | Gantt chart |
| Methodology | Simple lists | Waterfall, Agile, Kanban |
| Team | Single user | Multi-user collaboration |
| AI Role | Cleanup & decompose | Estimation & risk analysis |

---

## 2. User Experience Flow

### 2.1 Project Views

```
┌─────────────────────────────────────────────────────────────────────┐
│  Project: Q3 Marketing Campaign                                      │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  [WBS] [Gantt] [Kanban] [Timeline] [Team]                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Planning Phase                              ████░░░░░░  40%     │
│     1.1 Research competitors                   ████████████ Done    │
│     1.2 Define target audience                 ████████░░░░ 70%     │
│         1.2.1 Survey existing customers        ████████████ Done    │
│         1.2.2 Analyze demographics             ████████░░░░ 80%     │
│     1.3 Set budget                             ░░░░░░░░░░░░ Blocked │
│         → Waiting on: Finance approval                              │
│                                                                      │
│  2. Execution Phase                             ░░░░░░░░░░░░  0%    │
│     2.1 Content creation                       ░░░░░░░░░░░░ Not started│
│     2.2 Design assets                          ░░░░░░░░░░░░ Not started│
│                                                                      │
│  ────────────────────────────────────────────────────────────────── │
│  Critical Path: 1.3 → 2.1 → 2.2 → Launch                           │
│  Risk: Budget approval delayed 3 days                                │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Gantt Chart View

```
         Week 1    Week 2    Week 3    Week 4    Week 5
         ─────────────────────────────────────────────────
Phase 1  ██████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
  1.1    ██████████████████
  1.2              ████████████████████
    1.2.1          ██████████
    1.2.2                    ██████████
  1.3                                  ████████
                                            ↓ (dependency)
Phase 2                                      ░░░░░░░░░░░░░░
  2.1                                        ██████████████
  2.2                                                ████████
```

### 2.3 Work Breakdown Structure (WBS)

**Materialized Path Pattern:**
```
Project Root (id: proj-1)
├── 1.0 Planning (path: "proj-1.node-a", depth: 0)
│   ├── 1.1 Research (path: "proj-1.node-a.node-b", depth: 1)
│   ├── 1.2 Audience (path: "proj-1.node-a.node-c", depth: 1)
│   │   ├── 1.2.1 Survey (path: "proj-1.node-a.node-c.node-d", depth: 2)
│   │   └── 1.2.2 Analyze (path: "proj-1.node-a.node-c.node-e", depth: 2)
│   └── 1.3 Budget (path: "proj-1.node-a.node-f", depth: 1)
│         └─ source_task_id: "task-xyz" ← Promoted from Flow Tasks!
└── 2.0 Execution (path: "proj-1.node-g", depth: 0)
    ├── 2.1 Content (path: "proj-1.node-g.node-h", depth: 1)
    └── 2.2 Design (path: "proj-1.node-g.node-i", depth: 1)
```

### 2.4 WBS Node Data Model (wbs_nodes table)

```go
// projects/models/wbs_node.go

type WBSNode struct {
    ID          uuid.UUID  `json:"id"`
    ProjectID   uuid.UUID  `json:"project_id"`

    // Hierarchy (unlimited depth)
    ParentID    *uuid.UUID `json:"parent_id"`
    Path        string     `json:"path"`     // ltree for fast tree queries
    Depth       int        `json:"depth"`
    WBSCode     string     `json:"wbs_code"` // "1.2.3"
    SortOrder   int        `json:"sort_order"`

    // Core (same fields as personal Task)
    Title       string     `json:"title"`
    Description *string    `json:"description"`
    AISummary   *string    `json:"ai_summary"`
    AISteps     []Step     `json:"ai_steps"`
    Status      string     `json:"status"`
    Priority    int        `json:"priority"`
    Complexity  int        `json:"complexity"`

    // Project-specific
    AssigneeID      *uuid.UUID `json:"assignee_id"`
    EstimatedHours  *int       `json:"estimated_hours"`
    ActualHours     *int       `json:"actual_hours"`
    ProgressPercent float64    `json:"progress_percent"`

    // Dates
    StartDate   *time.Time `json:"start_date"`
    EndDate     *time.Time `json:"end_date"`
    DueDate     *time.Time `json:"due_date"`
    CompletedAt *time.Time `json:"completed_at"`

    // ═══ SOURCE TRACKING (if promoted from Flow Tasks) ═══
    SourceUserID  *uuid.UUID `json:"source_user_id"`  // Who promoted it
    SourceTaskID  *uuid.UUID `json:"source_task_id"`  // Original task ID in tasks_db
    PromotedAt    *time.Time `json:"promoted_at"`

    // Timestamps
    CreatedAt   time.Time  `json:"created_at"`
    UpdatedAt   time.Time  `json:"updated_at"`
    DeletedAt   *time.Time `json:"deleted_at"`
}
```

**Note:** `source_task_id` is informational only. There is NO automatic sync between the personal task and the WBS node. They are independent copies after promotion.

---

## 3. Flutter App Architecture

### 3.1 Project Structure

```
apps/flow_projects/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   ├── theme/
│   │   ├── router/
│   │   └── di/
│   │
│   ├── features/
│   │   ├── auth/                    # Shared with Flow Tasks
│   │   │   └── ...
│   │   │
│   │   ├── projects/
│   │   │   ├── data/
│   │   │   │   ├── project_repository.dart
│   │   │   │   ├── project_local_source.dart
│   │   │   │   └── project_remote_source.dart
│   │   │   ├── domain/
│   │   │   │   ├── project.dart
│   │   │   │   ├── methodology.dart
│   │   │   │   └── project_stats.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── project_list_screen.dart
│   │   │   │   │   ├── project_detail_screen.dart
│   │   │   │   │   └── project_create_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── project_card.dart
│   │   │   │       ├── project_header.dart
│   │   │   │       └── methodology_picker.dart
│   │   │   └── providers/
│   │   │       ├── project_list_provider.dart
│   │   │       └── project_detail_provider.dart
│   │   │
│   │   ├── wbs/                      # Work Breakdown Structure
│   │   │   ├── data/
│   │   │   │   └── wbs_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── wbs_node.dart
│   │   │   │   └── wbs_tree.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── wbs_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── wbs_tree_view.dart
│   │   │   │       ├── wbs_node_tile.dart
│   │   │   │       └── wbs_add_node.dart
│   │   │   └── providers/
│   │   │       └── wbs_provider.dart
│   │   │
│   │   ├── gantt/                    # Gantt Chart
│   │   │   ├── domain/
│   │   │   │   ├── gantt_bar.dart
│   │   │   │   ├── gantt_dependency.dart
│   │   │   │   └── time_scale.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── gantt_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── gantt_chart.dart
│   │   │   │       ├── gantt_bar_widget.dart
│   │   │   │       ├── gantt_header.dart
│   │   │   │       ├── gantt_grid.dart
│   │   │   │       └── dependency_line.dart
│   │   │   └── providers/
│   │   │       └── gantt_provider.dart
│   │   │
│   │   ├── kanban/                   # Kanban Board
│   │   │   ├── domain/
│   │   │   │   ├── kanban_column.dart
│   │   │   │   └── kanban_card.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── kanban_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── kanban_board.dart
│   │   │   │       ├── kanban_column_widget.dart
│   │   │   │       └── kanban_card_widget.dart
│   │   │   └── providers/
│   │   │       └── kanban_provider.dart
│   │   │
│   │   ├── dependencies/             # Task Dependencies
│   │   │   ├── data/
│   │   │   │   └── dependency_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── dependency.dart
│   │   │   │   ├── dependency_type.dart
│   │   │   │   └── critical_path.dart
│   │   │   ├── presentation/
│   │   │   │   └── widgets/
│   │   │   │       ├── dependency_editor.dart
│   │   │   │       └── critical_path_view.dart
│   │   │   └── providers/
│   │   │       └── dependency_provider.dart
│   │   │
│   │   ├── timeline/                 # Timeline View
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── timeline_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── timeline_view.dart
│   │   │   │       └── milestone_marker.dart
│   │   │   └── providers/
│   │   │       └── timeline_provider.dart
│   │   │
│   │   ├── team/                     # Team Collaboration
│   │   │   ├── data/
│   │   │   │   └── team_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── team_member.dart
│   │   │   │   └── assignment.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── team_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── member_list.dart
│   │   │   │       ├── workload_chart.dart
│   │   │   │       └── assignment_dialog.dart
│   │   │   └── providers/
│   │   │       └── team_provider.dart
│   │   │
│   │   ├── ai/                       # AI Features
│   │   │   ├── presentation/
│   │   │   │   └── widgets/
│   │   │   │       ├── ai_estimation.dart
│   │   │   │       ├── risk_analysis.dart
│   │   │   │       └── auto_schedule.dart
│   │   │   └── providers/
│   │   │       └── ai_project_provider.dart
│   │   │
│   │   ├── export/                   # Export to Flow Tasks
│   │   │   ├── presentation/
│   │   │   │   └── widgets/
│   │   │   │       └── export_to_tasks_dialog.dart
│   │   │   └── providers/
│   │   │       └── export_provider.dart
│   │   │
│   │   └── settings/
│   │       └── ...
│   │
│   └── shared/
│       ├── widgets/
│       └── utils/
│
├── test/
├── pubspec.yaml
└── l10n/
```

### 3.2 Domain Models

```dart
// lib/features/projects/domain/project.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project.freezed.dart';
part 'project.g.dart';

@freezed
class Project with _$Project {
  const factory Project({
    required String id,
    required String userId,
    required String name,
    String? description,
    @Default(Methodology.waterfall) Methodology methodology,
    @Default(ProjectStatus.planning) ProjectStatus status,

    // Dates
    DateTime? startDate,
    DateTime? targetEndDate,
    DateTime? actualEndDate,

    // Team
    String? ownerId,
    @Default([]) List<String> teamIds,

    // AI metadata
    String? aiSummary,
    @Default({}) Map<String, dynamic> aiGoals,

    // Settings
    @Default({}) Map<String, dynamic> settings,

    // Stats (computed)
    ProjectStats? stats,

    // Timestamps
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Project;

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);
}

enum Methodology {
  waterfall,
  agile,
  hybrid,
  kanban,
}

enum ProjectStatus {
  planning,
  active,
  onHold,
  completed,
  cancelled,
}

@freezed
class ProjectStats with _$ProjectStats {
  const factory ProjectStats({
    required int totalTasks,
    required int completedTasks,
    required int inProgressTasks,
    required int blockedTasks,
    required double progressPercent,
    required int daysRemaining,
    required int daysOverdue,
    List<String>? criticalPath,
    List<RiskItem>? risks,
  }) = _ProjectStats;

  factory ProjectStats.fromJson(Map<String, dynamic> json) =>
      _$ProjectStatsFromJson(json);
}
```

```dart
// lib/features/wbs/domain/wbs_node.dart

@freezed
class WbsNode with _$WbsNode {
  const factory WbsNode({
    required String id,
    required String projectId,
    String? parentId,
    required String path,        // ltree path for hierarchy
    required int depth,
    required String wbsCode,     // "1.2.3" style code

    required String title,
    String? description,
    String? aiSummary,
    @Default([]) List<TaskStep> aiSteps,

    @Default(TaskStatus.pending) TaskStatus status,
    @Default(0) int priority,
    @Default(1) int complexity,

    // Scheduling
    DateTime? startDate,
    DateTime? endDate,
    int? estimatedHours,
    int? actualHours,

    // Assignment
    String? assigneeId,

    // Progress
    @Default(0) double progressPercent,

    // Children (for tree rendering)
    @Default([]) List<WbsNode> children,

    // Timestamps
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _WbsNode;

  factory WbsNode.fromJson(Map<String, dynamic> json) =>
      _$WbsNodeFromJson(json);
}
```

```dart
// lib/features/dependencies/domain/dependency.dart

@freezed
class TaskDependency with _$TaskDependency {
  const factory TaskDependency({
    required String id,
    required String predecessorId,
    required String successorId,
    @Default(DependencyType.finishToStart) DependencyType type,
    @Default(0) int lagDays,
    required DateTime createdAt,
  }) = _TaskDependency;

  factory TaskDependency.fromJson(Map<String, dynamic> json) =>
      _$TaskDependencyFromJson(json);
}

enum DependencyType {
  finishToStart,   // FS: Successor starts after predecessor finishes
  startToStart,    // SS: Both start together
  finishToFinish,  // FF: Both finish together
  startToFinish,   // SF: Predecessor starts after successor finishes (rare)
}
```

### 3.3 Gantt Chart Implementation

```dart
// lib/features/gantt/presentation/widgets/gantt_chart.dart

class GanttChart extends ConsumerWidget {
  final String projectId;

  const GanttChart({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ganttData = ref.watch(ganttDataProvider(projectId));

    return ganttData.when(
      data: (data) => _buildChart(context, data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e),
    );
  }

  Widget _buildChart(BuildContext context, GanttData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final timeScale = TimeScale(
          startDate: data.projectStartDate,
          endDate: data.projectEndDate,
          viewWidth: constraints.maxWidth - 250, // Task names column
        );

        return Row(
          children: [
            // Task names column (fixed)
            SizedBox(
              width: 250,
              child: _buildTaskNames(data.nodes),
            ),

            // Gantt bars (scrollable horizontally)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: timeScale.totalWidth,
                  child: Stack(
                    children: [
                      // Grid lines
                      GanttGrid(timeScale: timeScale),

                      // Header (dates)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: GanttHeader(timeScale: timeScale),
                      ),

                      // Bars
                      ...data.nodes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final node = entry.value;
                        return Positioned(
                          top: 50 + (index * 40), // Row height
                          left: timeScale.dateToX(node.startDate),
                          child: GanttBarWidget(
                            node: node,
                            width: timeScale.durationToWidth(
                              node.startDate,
                              node.endDate,
                            ),
                          ),
                        );
                      }),

                      // Dependency lines
                      ...data.dependencies.map((dep) => DependencyLine(
                        dependency: dep,
                        timeScale: timeScale,
                        nodes: data.nodes,
                      )),

                      // Today marker
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: timeScale.dateToX(DateTime.now()),
                        child: Container(
                          width: 2,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTaskNames(List<WbsNode> nodes) {
    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return Container(
          height: 40,
          padding: EdgeInsets.only(left: node.depth * 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              if (node.children.isNotEmpty)
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: Colors.grey,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${node.wbsCode} ${node.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

```dart
// lib/features/gantt/domain/time_scale.dart

class TimeScale {
  final DateTime startDate;
  final DateTime endDate;
  final double viewWidth;
  final double dayWidth;

  TimeScale({
    required this.startDate,
    required this.endDate,
    required this.viewWidth,
    this.dayWidth = 30, // pixels per day
  });

  int get totalDays => endDate.difference(startDate).inDays + 1;
  double get totalWidth => totalDays * dayWidth;

  double dateToX(DateTime? date) {
    if (date == null) return 0;
    final days = date.difference(startDate).inDays;
    return days * dayWidth;
  }

  double durationToWidth(DateTime? start, DateTime? end) {
    if (start == null || end == null) return dayWidth; // minimum 1 day
    final days = end.difference(start).inDays + 1;
    return days * dayWidth;
  }

  DateTime xToDate(double x) {
    final days = (x / dayWidth).round();
    return startDate.add(Duration(days: days));
  }
}
```

### 3.4 Critical Path Calculation

```dart
// lib/features/dependencies/domain/critical_path.dart

class CriticalPathCalculator {
  /// Calculate critical path using forward and backward pass
  List<String> calculate(List<WbsNode> nodes, List<TaskDependency> deps) {
    // Build adjacency lists
    final successors = <String, List<String>>{};
    final predecessors = <String, List<String>>{};
    final lagDays = <String, Map<String, int>>{};

    for (final dep in deps) {
      successors.putIfAbsent(dep.predecessorId, () => []).add(dep.successorId);
      predecessors.putIfAbsent(dep.successorId, () => []).add(dep.predecessorId);
      lagDays.putIfAbsent(dep.predecessorId, () => {})[dep.successorId] = dep.lagDays;
    }

    // Forward pass: Calculate Early Start (ES) and Early Finish (EF)
    final es = <String, int>{};  // Early Start
    final ef = <String, int>{};  // Early Finish
    final duration = <String, int>{};

    for (final node in nodes) {
      duration[node.id] = node.estimatedHours ?? 8; // Default 1 day
    }

    // Topological sort for forward pass
    final sorted = _topologicalSort(nodes, predecessors);

    for (final nodeId in sorted) {
      final preds = predecessors[nodeId] ?? [];
      if (preds.isEmpty) {
        es[nodeId] = 0;
      } else {
        es[nodeId] = preds.map((p) {
          final lag = lagDays[p]?[nodeId] ?? 0;
          return ef[p]! + lag;
        }).reduce(max);
      }
      ef[nodeId] = es[nodeId]! + duration[nodeId]!;
    }

    // Project duration
    final projectDuration = ef.values.reduce(max);

    // Backward pass: Calculate Late Start (LS) and Late Finish (LF)
    final ls = <String, int>{};  // Late Start
    final lf = <String, int>{};  // Late Finish

    for (final nodeId in sorted.reversed) {
      final succs = successors[nodeId] ?? [];
      if (succs.isEmpty) {
        lf[nodeId] = projectDuration;
      } else {
        lf[nodeId] = succs.map((s) {
          final lag = lagDays[nodeId]?[s] ?? 0;
          return ls[s]! - lag;
        }).reduce(min);
      }
      ls[nodeId] = lf[nodeId]! - duration[nodeId]!;
    }

    // Critical path: nodes where ES == LS (zero float)
    final criticalPath = <String>[];
    for (final nodeId in sorted) {
      if (es[nodeId] == ls[nodeId]) {
        criticalPath.add(nodeId);
      }
    }

    return criticalPath;
  }

  List<String> _topologicalSort(
    List<WbsNode> nodes,
    Map<String, List<String>> predecessors,
  ) {
    final visited = <String>{};
    final result = <String>[];

    void visit(String nodeId) {
      if (visited.contains(nodeId)) return;
      visited.add(nodeId);

      for (final pred in predecessors[nodeId] ?? []) {
        visit(pred);
      }

      result.add(nodeId);
    }

    for (final node in nodes) {
      visit(node.id);
    }

    return result;
  }
}
```

### 3.5 Dependency Editor

```dart
// lib/features/dependencies/presentation/widgets/dependency_editor.dart

class DependencyEditor extends ConsumerStatefulWidget {
  final String taskId;

  const DependencyEditor({required this.taskId});

  @override
  ConsumerState<DependencyEditor> createState() => _DependencyEditorState();
}

class _DependencyEditorState extends ConsumerState<DependencyEditor> {
  DependencyType _selectedType = DependencyType.finishToStart;
  int _lagDays = 0;
  String? _selectedPredecessorId;

  @override
  Widget build(BuildContext context) {
    final projectTasks = ref.watch(projectTasksProvider);
    final currentDeps = ref.watch(taskDependenciesProvider(widget.taskId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dependencies',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),

        // Current dependencies
        currentDeps.when(
          data: (deps) => Column(
            children: deps.map((dep) => ListTile(
              leading: const Icon(Icons.link),
              title: Text(_getTaskTitle(dep.predecessorId)),
              subtitle: Text('${dep.type.displayName} + ${dep.lagDays} days'),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _removeDependency(dep.id),
              ),
            )).toList(),
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),

        const Divider(),

        // Add new dependency
        Text(
          'Add Dependency',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),

        // Predecessor selector
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Depends on (predecessor)',
          ),
          value: _selectedPredecessorId,
          items: projectTasks.valueOrNull
              ?.where((t) => t.id != widget.taskId)
              .map((t) => DropdownMenuItem(
                    value: t.id,
                    child: Text('${t.wbsCode} ${t.title}'),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedPredecessorId = value),
        ),

        const SizedBox(height: 8),

        // Dependency type
        DropdownButtonFormField<DependencyType>(
          decoration: const InputDecoration(
            labelText: 'Dependency Type',
          ),
          value: _selectedType,
          items: DependencyType.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.displayName),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedType = value!),
        ),

        const SizedBox(height: 8),

        // Lag days
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Lag (days)',
                ),
                keyboardType: TextInputType.number,
                initialValue: '0',
                onChanged: (value) => _lagDays = int.tryParse(value) ?? 0,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _selectedPredecessorId == null ? null : _addDependency,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  void _addDependency() async {
    await ref.read(dependencyRepositoryProvider).createDependency(
      DependencyCreate(
        predecessorId: _selectedPredecessorId!,
        successorId: widget.taskId,
        type: _selectedType,
        lagDays: _lagDays,
      ),
    );

    setState(() {
      _selectedPredecessorId = null;
      _lagDays = 0;
    });
  }

  void _removeDependency(String depId) async {
    await ref.read(dependencyRepositoryProvider).deleteDependency(depId);
  }
}

extension DependencyTypeExt on DependencyType {
  String get displayName {
    switch (this) {
      case DependencyType.finishToStart:
        return 'Finish-to-Start (FS)';
      case DependencyType.startToStart:
        return 'Start-to-Start (SS)';
      case DependencyType.finishToFinish:
        return 'Finish-to-Finish (FF)';
      case DependencyType.startToFinish:
        return 'Start-to-Finish (SF)';
    }
  }
}
```

---

## 4. AI Features in Flow Projects

### 4.1 AI Estimation

```dart
// lib/features/ai/presentation/widgets/ai_estimation.dart

class AiEstimation extends ConsumerWidget {
  final String projectId;

  const AiEstimation({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimation = ref.watch(aiEstimationProvider(projectId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'AI Estimation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.refresh(aiEstimationProvider(projectId)),
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const Divider(),

            estimation.when(
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEstimateRow(
                    'Optimistic',
                    '${data.optimisticDays} days',
                    Colors.green,
                  ),
                  _buildEstimateRow(
                    'Most Likely',
                    '${data.mostLikelyDays} days',
                    Colors.blue,
                  ),
                  _buildEstimateRow(
                    'Pessimistic',
                    '${data.pessimisticDays} days',
                    Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Confidence: ${(data.confidence * 100).toInt()}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on: ${data.reasoning}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimateRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
```

### 4.2 Risk Analysis

```dart
// lib/features/ai/presentation/widgets/risk_analysis.dart

class RiskAnalysis extends ConsumerWidget {
  final String projectId;

  const RiskAnalysis({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final risks = ref.watch(aiRiskAnalysisProvider(projectId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Risk Analysis',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),

            risks.when(
              data: (riskList) => Column(
                children: riskList.map((risk) => _buildRiskItem(risk)).toList(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskItem(RiskItem risk) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _severityColor(risk.severity),
        radius: 16,
        child: Text(
          risk.severity.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(risk.title),
      subtitle: Text(risk.description),
      trailing: Text(
        '${(risk.probability * 100).toInt()}%',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _severityColor(int severity) {
    if (severity >= 8) return Colors.red;
    if (severity >= 5) return Colors.orange;
    return Colors.yellow.shade700;
  }
}

@freezed
class RiskItem with _$RiskItem {
  const factory RiskItem({
    required String title,
    required String description,
    required int severity,      // 1-10
    required double probability, // 0.0-1.0
    String? mitigation,
    String? affectedTaskId,
  }) = _RiskItem;

  factory RiskItem.fromJson(Map<String, dynamic> json) =>
      _$RiskItemFromJson(json);
}
```

### 4.3 Auto-Schedule

```dart
// lib/features/ai/presentation/widgets/auto_schedule.dart

class AutoScheduleButton extends ConsumerWidget {
  final String projectId;

  const AutoScheduleButton({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.auto_fix_high),
      label: const Text('Auto-Schedule'),
      onPressed: () => _showAutoScheduleDialog(context, ref),
    );
  }

  void _showAutoScheduleDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-Schedule Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI will analyze your project and suggest optimal scheduling based on:',
            ),
            const SizedBox(height: 8),
            const Text('• Task dependencies'),
            const Text('• Team availability'),
            const Text('• Historical completion data'),
            const Text('• Resource constraints'),
            const SizedBox(height: 16),
            const Text(
              'This will update start/end dates for all unscheduled tasks.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _runAutoSchedule(context, ref);
            },
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
  }

  Future<void> _runAutoSchedule(BuildContext context, WidgetRef ref) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('AI is scheduling your project...'),
          ],
        ),
      ),
    );

    try {
      await ref.read(aiProjectProvider).autoSchedule(projectId);
      Navigator.pop(context); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project scheduled successfully')),
      );
    } catch (e) {
      Navigator.pop(context); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
```

---

## 5. Export to Flow Tasks

### 5.1 Export Logic

When a user wants to work on a specific branch of the WBS in Flow Tasks:

```dart
// lib/features/export/providers/export_provider.dart

class ExportToTasksService {
  final TaskRepository _taskRepo;
  final WbsRepository _wbsRepo;

  /// Export a WBS node to Flow Tasks
  /// Only exports the node and its IMMEDIATE children (2-layer limit)
  Future<void> exportToTasks(String nodeId) async {
    final node = await _wbsRepo.getNode(nodeId);
    if (node == null) throw NotFoundException('Node not found');

    // Create parent task in Flow Tasks
    final parentTask = await _taskRepo.createTask(TaskCreate(
      userId: node.userId,
      title: node.title,
      description: node.description,
      aiSummary: node.aiSummary,
      projectId: node.projectId,  // Link back to project
      metadata: {
        'exported_from_wbs': nodeId,
        'wbs_code': node.wbsCode,
      },
    ));

    // Get immediate children only (respect 2-layer limit)
    final children = await _wbsRepo.getChildren(nodeId, maxDepth: 1);

    for (final child in children) {
      await _taskRepo.createTask(TaskCreate(
        userId: child.userId,
        parentId: parentTask.id,
        title: child.title,
        description: child.description,
        aiSummary: child.aiSummary,
        depth: 1,
        metadata: {
          'exported_from_wbs': child.id,
          'wbs_code': child.wbsCode,
        },
      ));
    }
  }

  /// Sync changes back from Flow Tasks to WBS
  Future<void> syncBackToWbs(String taskId) async {
    final task = await _taskRepo.getTask(taskId);
    if (task == null) return;

    final wbsNodeId = task.metadata['exported_from_wbs'] as String?;
    if (wbsNodeId == null) return;

    // Update WBS node status
    await _wbsRepo.updateNode(wbsNodeId, WbsNodeUpdate(
      status: task.status,
      completedAt: task.completedAt,
      actualHours: _calculateActualHours(task),
    ));
  }
}
```

---

## 6. Team Collaboration

### 6.1 Team Data Model

```dart
// lib/features/team/domain/team_member.dart

@freezed
class TeamMember with _$TeamMember {
  const factory TeamMember({
    required String userId,
    required String name,
    String? avatarUrl,
    required TeamRole role,
    required DateTime joinedAt,

    // Workload
    @Default(0) int assignedTasks,
    @Default(0) int assignedHours,
    @Default(1.0) double availability, // 0.0-1.0 (part-time)
  }) = _TeamMember;

  factory TeamMember.fromJson(Map<String, dynamic> json) =>
      _$TeamMemberFromJson(json);
}

enum TeamRole {
  owner,
  admin,
  member,
  viewer,
}

@freezed
class TaskAssignment with _$TaskAssignment {
  const factory TaskAssignment({
    required String taskId,
    required String userId,
    required DateTime assignedAt,
    String? assignedBy,
  }) = _TaskAssignment;

  factory TaskAssignment.fromJson(Map<String, dynamic> json) =>
      _$TaskAssignmentFromJson(json);
}
```

### 6.2 Workload View

```dart
// lib/features/team/presentation/widgets/workload_chart.dart

class WorkloadChart extends StatelessWidget {
  final List<TeamMember> members;
  final Map<String, int> hoursPerMember;

  const WorkloadChart({
    required this.members,
    required this.hoursPerMember,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Team Workload',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        ...members.map((member) {
          final hours = hoursPerMember[member.userId] ?? 0;
          final maxHours = 40 * member.availability; // 40h week * availability
          final percent = (hours / maxHours).clamp(0.0, 1.5);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: member.avatarUrl != null
                          ? NetworkImage(member.avatarUrl!)
                          : null,
                      child: member.avatarUrl == null
                          ? Text(member.name[0])
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(member.name)),
                    Text('${hours}h / ${maxHours.toInt()}h'),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percent,
                  backgroundColor: Colors.grey.shade200,
                  color: _workloadColor(percent),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _workloadColor(double percent) {
    if (percent > 1.0) return Colors.red;       // Overloaded
    if (percent > 0.8) return Colors.orange;    // Near capacity
    if (percent > 0.5) return Colors.green;     // Good
    return Colors.blue;                          // Underutilized
  }
}
```

---

## 7. Navigation Structure

```
Flow Projects App
├── Projects List (default)
│   └── Active/Completed/Archived tabs
├── Project Detail
│   ├── Overview (stats, risks, timeline)
│   ├── WBS (tree view)
│   ├── Gantt (chart view)
│   ├── Kanban (board view)
│   ├── Team (members, workload)
│   └── Settings
├── Task Detail (WBS node)
│   ├── Details
│   ├── Dependencies
│   ├── Assignments
│   └── Export to Tasks
└── Settings
    ├── Account
    ├── Integrations
    └── Notifications
```

---

## 8. Backend API Endpoints (Project-specific)

```
# Projects
GET    /api/v1/projects
POST   /api/v1/projects
GET    /api/v1/projects/:id
PUT    /api/v1/projects/:id
DELETE /api/v1/projects/:id
GET    /api/v1/projects/:id/stats

# WBS
GET    /api/v1/projects/:id/wbs              # Get full tree
POST   /api/v1/projects/:id/wbs              # Add node
GET    /api/v1/wbs/:nodeId
PUT    /api/v1/wbs/:nodeId
DELETE /api/v1/wbs/:nodeId
POST   /api/v1/wbs/:nodeId/reorder           # Change parent/position

# Dependencies
GET    /api/v1/projects/:id/dependencies
POST   /api/v1/dependencies
DELETE /api/v1/dependencies/:id
GET    /api/v1/projects/:id/critical-path

# Team
GET    /api/v1/projects/:id/team
POST   /api/v1/projects/:id/team/invite
DELETE /api/v1/projects/:id/team/:userId
PUT    /api/v1/projects/:id/team/:userId/role
GET    /api/v1/projects/:id/team/workload

# Assignments
POST   /api/v1/wbs/:nodeId/assign
DELETE /api/v1/wbs/:nodeId/unassign

# AI
POST   /api/v1/projects/:id/ai/estimate
POST   /api/v1/projects/:id/ai/risks
POST   /api/v1/projects/:id/ai/schedule
POST   /api/v1/projects/:id/ai/wbs-suggest    # Generate WBS from description

# Export
POST   /api/v1/wbs/:nodeId/export-to-tasks
POST   /api/v1/tasks/:taskId/sync-to-wbs
```

---

## 9. Launch Checklist

### Phase 1 (MVP)
- [ ] Project CRUD
- [ ] Basic WBS (tree view)
- [ ] Task creation within projects
- [ ] Simple Gantt (view only)
- [ ] Sync with Flow Tasks (import promoted tasks)

### Phase 2
- [ ] Dependencies (FS only)
- [ ] Critical path calculation
- [ ] Gantt editing (drag to reschedule)
- [ ] AI estimation

### Phase 3
- [ ] Team collaboration
- [ ] Assignments
- [ ] Workload view
- [ ] All dependency types
- [ ] Risk analysis

### Phase 4
- [ ] Kanban view
- [ ] Auto-scheduling
- [ ] Advanced AI features
- [ ] Export to Tasks

---

## 10. Integration Points with Flow Tasks

| Flow Tasks | ← Sync → | Flow Projects |
|------------|----------|---------------|
| Complex task | Promote → | New project root |
| Task with depth>1 blocked | Suggest → | Convert to project |
| Exported WBS node | ← Export | WBS branch |
| Task completed | Sync → | WBS node status |

**Key Rule:** Flow Tasks is the "daily driver" for execution. Flow Projects is for planning and tracking. Users should be able to work in Flow Tasks 90% of the time, only switching to Projects for planning sessions.

---

## Next Steps

1. Build shared Flutter packages first (flow_api, flow_models, flow_database)
2. Implement Flow Tasks MVP
3. Add project import (promoted tasks)
4. Build basic WBS view
5. Add Gantt chart
6. Implement dependencies
7. Add team features
