@flowEntities @contentrepository
Feature: Document.Folder node type registers correctly and the `hideurisegment` column reflects the event payload

  The projection's `hideUriSegmentForInsert` is a pure function over the event's
  property values — so we assert both directions (true / false) explicitly via
  the row written into `*_documenturipath_uri`.

  Background:
    Given using no content dimensions
    And using the following node types:
    """yaml
    'Neos.Neos:Sites':
      superTypes:
        'Neos.ContentRepository:Root': true
    'Neos.Neos:Document': {}
    'Neos.Neos:Content': {}
    'Neos.Neos:Test.Routing.Page':
      superTypes:
        'Neos.Neos:Document': true
      properties:
        uriPathSegment:
          type: string
    'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment':
      abstract: true
      properties:
        hideSegmentInUriPath:
          type: boolean
          defaultValue: true
    'Sandstorm.NodeTypes.Folder:Document.Folder':
      superTypes:
        'Neos.Neos:Document': true
        'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment': true
      properties:
        uriPathSegment:
          type: string
    """
    And using identifier "default", I define a content repository
    And I am in content repository "default"
    And I am user identified by "initiating-user-identifier"
    When the command CreateRootWorkspace is executed with payload:
      | Key                | Value           |
      | workspaceName      | "live"          |
      | newContentStreamId | "cs-identifier" |
    And I am in workspace "live" and dimension space point {}
    And the command CreateRootNodeAggregateWithNode is executed with payload:
      | Key             | Value                    |
      | nodeAggregateId | "lady-eleonode-rootford" |
      | nodeTypeName    | "Neos.Neos:Sites"        |
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId  | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                            | nodeName |
      | site-of-folders  | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                               | node1    |

  Scenario: Creating a Document.Folder with hideSegmentInUriPath=true marks the projection row transparent
    When the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId | parentNodeAggregateId | nodeTypeName                                  | initialPropertyValues                                                       |
      | folder-hidden   | site-of-folders       | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-hidden", "hideSegmentInUriPath": true}           |
    Then I expect the documenturipath table to contain exactly:
      | nodeaggregateid          | uripath          | hideurisegment |
      | "lady-eleonode-rootford" | ""               | 0              |
      | "site-of-folders"        | ""               | 0              |
      | "folder-hidden"          | "folder-hidden"  | 1              |

  Scenario: Creating a Document.Folder with hideSegmentInUriPath=false marks the projection row opaque
    When the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId | parentNodeAggregateId | nodeTypeName                                  | initialPropertyValues                                                      |
      | folder-visible  | site-of-folders       | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-visible", "hideSegmentInUriPath": false}        |
    Then I expect the documenturipath table to contain exactly:
      | nodeaggregateid          | uripath          | hideurisegment |
      | "lady-eleonode-rootford" | ""               | 0              |
      | "site-of-folders"        | ""               | 0              |
      | "folder-visible"         | "folder-visible" | 0              |
