class Workflow {
  final String id;
  final String name;
  final bool isActive;
  final String triggerType;
  final String triggerConfig;
  final List<WorkflowActionModel> actions;

  Workflow({
    required this.id,
    required this.name,
    required this.isActive,
    required this.triggerType,
    required this.triggerConfig,
    required this.actions,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unnamed Workflow',
      isActive: json['isActive'] ?? true,
      triggerType: json['triggerType'] ?? 'UNKNOWN',
      triggerConfig: json['triggerConfig'] ?? '{}',
      actions: (json['actions'] as List?)
              ?.map((a) => WorkflowActionModel.fromJson(a))
              .toList() ??
          [],
    );
  }
}

class WorkflowActionModel {
  final String actionType;
  final String actionConfig;
  final int order;

  WorkflowActionModel({
    required this.actionType,
    required this.actionConfig,
    required this.order,
  });

  factory WorkflowActionModel.fromJson(Map<String, dynamic> json) {
    return WorkflowActionModel(
      actionType: json['actionType'] ?? 'SEND_NOTIFICATION',
      actionConfig: json['actionConfig'] ?? '{}',
      order: json['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'actionConfig': actionConfig,
        'order': order,
      };
}
