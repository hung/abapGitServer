REPORT zags_migration_01.
* Migration, add REPO key in ZAGS_OBJECTS, old data is not deleted

DATA: gt_objects TYPE zags_objects_tt.


START-OF-SELECTION.
  PERFORM run.

CLASS lcl_visitor DEFINITION FINAL.

  PUBLIC SECTION.
    CLASS-METHODS: visit
      IMPORTING it_sha1        TYPE zags_sha1_tt
      RETURNING VALUE(rt_sha1) TYPE zags_sha1_tt
      RAISING   zcx_abapgit_exception.

ENDCLASS.

CLASS lcl_visitor IMPLEMENTATION.

  METHOD visit.

    DATA: ls_commit TYPE zcl_ags_obj_commit=>ty_commit,
          lt_tree   TYPE zcl_ags_obj_tree=>ty_tree_tt.

    FIELD-SYMBOLS: <lv_sha1>   LIKE LINE OF it_sha1,
                   <ls_tree>   LIKE LINE OF lt_tree,
                   <ls_object> LIKE LINE OF gt_objects.


    rt_sha1 = it_sha1.

    LOOP AT rt_sha1 ASSIGNING <lv_sha1>.
      READ TABLE gt_objects WITH KEY
        repo = '' sha1 = <lv_sha1>
        ASSIGNING <ls_object>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      CASE <ls_object>-type.
        WHEN zif_ags_constants=>c_type-tree.
          lt_tree = zcl_abapgit_git_pack=>decode_tree( <ls_object>-data_raw ).
          LOOP AT lt_tree ASSIGNING <ls_tree>.
            APPEND <ls_tree>-sha1 TO rt_sha1.
          ENDLOOP.
        WHEN zif_ags_constants=>c_type-commit.
          ls_commit = zcl_abapgit_git_pack=>decode_commit( <ls_object>-data_raw ).
          IF NOT ls_commit-parent IS INITIAL.
            APPEND ls_commit-parent TO rt_sha1.
          ENDIF.
          IF NOT ls_commit-parent2 IS INITIAL.
            APPEND ls_commit-parent2 TO rt_sha1.
          ENDIF.
          APPEND ls_commit-tree TO rt_sha1.
        WHEN zif_ags_constants=>c_type-blob.
          CONTINUE.
        WHEN OTHERS.
          ASSERT 0 = 1.
      ENDCASE.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

FORM run RAISING zcx_ags_error zcx_abapgit_exception.

  DATA: lt_repos    TYPE zags_repos_tt,
        lt_sha1     TYPE zags_sha1_tt,
        lt_result   TYPE zags_sha1_tt,
        lt_branches TYPE zcl_ags_repo=>ty_branches_tt.

  FIELD-SYMBOLS: <ls_repo>   LIKE LINE OF lt_repos,
                 <lo_branch> LIKE LINE OF lt_branches.


  gt_objects = zcl_ags_db=>get_objects( )->list( ).

  lt_repos = zcl_ags_repo=>list( ).

  LOOP AT lt_repos ASSIGNING <ls_repo>.
    CLEAR lt_sha1.

    lt_branches = zcl_ags_repo=>get_instance( <ls_repo>-name )->list_branches( ).
    LOOP AT lt_branches ASSIGNING <lo_branch>.
      APPEND <lo_branch>->get_data( )-sha1 TO lt_sha1.
    ENDLOOP.

    CLEAR lt_result.
    lt_result = lcl_visitor=>visit( lt_sha1 ).
    PERFORM save USING <ls_repo>-repo lt_result.
  ENDLOOP.

  WRITE: / 'Done'(001).

ENDFORM.

FORM save USING pv_repo TYPE zags_repos-repo
                pt_sha1 TYPE zags_sha1_tt.

  DATA: ls_object TYPE zags_objects.

  FIELD-SYMBOLS: <lv_sha1>   LIKE LINE OF pt_sha1,
                 <ls_object> LIKE LINE OF gt_objects.


  SORT pt_sha1 ASCENDING.
  DELETE ADJACENT DUPLICATES FROM pt_sha1.

  ASSERT NOT pv_repo IS INITIAL.

  LOOP AT pt_sha1 ASSIGNING <lv_sha1>.
    READ TABLE gt_objects ASSIGNING <ls_object>
      WITH KEY repo = '' sha1 = <lv_sha1>.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

* note that in the old setup an object could be shared between repos
    CLEAR ls_object.
    ls_object = <ls_object>.
    ls_object-repo = pv_repo.

    zcl_ags_db=>get_objects( )->modify( ls_object ).
  ENDLOOP.

ENDFORM.
