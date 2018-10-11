
function WorldEditor::onSelect( %this, %obj, %isLastSelection, %isFirstSelection )
{
    EditorTree.addSelectionObjectId( %obj, %isLastSelection, %isFirstSelection );

    _setShadowVizLight( %obj );

    if ( isObject( %obj ) && %obj.isMethod( "onEditorSelect" ) )
        %obj.onEditorSelect( %this.getSelectionSize() );

    EditorGui.currentEditor.onObjectSelected( %obj );

    // Inform the camera
    EditorOrbitCameraSelectChange(%this.getSelectionSize(), %this.getSelectionCentroid());

    EditorGuiStatusBar.setSelectionObjectsByCount(%this.getSelectionSize());

    // Update the materialEditorList
    $Tools::materialEditorList = %obj.getId();

    // Used to help the Material Editor( the M.E doesn't utilize its own TS control )
    // so this dirty extension is used to fake it
    if ( MaterialEditorPreviewWindow.isVisible() )
        MaterialEditorGui.prepareActiveObject();

    // Update the Transform Selection window
    ETransformSelection.onSelectionChanged();
}

function WorldEditor::onMultiSelect( %this, %set )
{
    // This is called when completing a drag selection ( on3DMouseUp )
    // so we can avoid calling onSelect for every object. We can only
    // do most of this stuff, like inspecting, on one object at a time anyway.

    %count = %set.getCount();
    %i = 0;

    foreach( %obj in %set )
    {
        if ( %obj.isMethod( "onEditorSelect" ) )
            %obj.onEditorSelect( %count );

        %i ++;
        EditorTree.addSelectionObjectId( %obj, %i == %count );
        EditorGui.currentEditor.onObjectSelected( %obj );
    }

    // Inform the camera
    EditorOrbitCameraSelectChange( %count, %this.getSelectionCentroid() );

    EditorGuiStatusBar.setSelectionObjectsByCount( EWorldEditor.getSelectionSize() );

    // Update the Transform Selection window, if it is
    // visible.

    if( ETransformSelection.isVisible() )
        ETransformSelection.onSelectionChanged();
}

function WorldEditor::onUnSelect( %this, %obj, %isLastSelection, %isFirstSelection )
{
    if ( isObject( %obj ) && %obj.isMethod( "onEditorUnselect" ) )
        %obj.onEditorUnselect();

    EditorGui.currentEditor.onObjectDeselected( %obj );

    Inspector.removeInspect( %obj );
    EditorTree.removeSelectionObjectId(%obj, %isLastSelection, %isFirstSelection );

    // Inform the camera
    EditorOrbitCameraSelectChange(%this.getSelectionSize(), %this.getSelectionCentroid());

    EditorGuiStatusBar.setSelectionObjectsByCount(%this.getSelectionSize());

    // Update the Transform Selection window
    ETransformSelection.onSelectionChanged();
}

function WorldEditor::onClearSelection( %this )
{
    EditorGui.currentEditor.onSelectionCleared();

    EditorTree.clearSelection();

    // Inform the camera
    EditorOrbitCameraSelectChange(%this.getSelectionSize(), %this.getSelectionCentroid());

    EditorGuiStatusBar.setSelectionObjectsByCount(%this.getSelectionSize());

    // Update the Transform Selection window
    ETransformSelection.onSelectionChanged();
}

function WorldEditor::onSelectionCentroidChanged( %this )
{
    // Inform the camera
    EditorOrbitCameraSelectChange(%this.getSelectionSize(), %this.getSelectionCentroid());

    // Refresh inspector.
    Inspector.refresh();
}

//////////////////////////////////////////////////////////////////////////

function WorldEditor::init(%this)
{
    // add objclasses which we do not want to collide with
    %this.ignoreObjClass(Sky);

    // editing modes
    %this.numEditModes = 3;
    %this.editMode[0]    = "move";
    %this.editMode[1]    = "rotate";
    %this.editMode[2]    = "scale";

    // context menu
    new GuiControl(WEContextPopupDlg, EditorGuiGroup)
    {
        profile = "ToolsGuiModelessDialogProfile";
        horizSizing = "width";
        vertSizing = "height";
        position = "0 0";
        extent = "640 480";
        minExtent = "8 8";
        visible = "1";
        setFirstResponder = "0";
        modal = "1";

        new GuiPopUpMenuCtrl(WEContextPopup)
        {
            profile = "ToolsGuiScrollProfile";
            position = "0 0";
            extent = "0 0";
            minExtent = "0 0";
            maxPopupHeight = "200";
            command = "canvas.popDialog(WEContextPopupDlg);";
        };
    };
    WEContextPopup.setVisible(false);

    // Make sure we have an active selection set.
    if( !%this.getActiveSelection() )
        %this.setActiveSelection( new WorldEditorSelection( EWorldEditorSelection ) );
}

//------------------------------------------------------------------------------

function WorldEditor::onDblClick(%this, %obj)
{
    // Commented out because making someone double click to do this is stupid
    // and has the possibility of moving hte object

    //Inspector.inspect(%obj);
    //InspectorNameEdit.setValue(%obj.getName());
}

function WorldEditor::onClick( %this, %obj )
{
    Inspector.addInspect( %obj );
}

function WorldEditor::onEndDrag( %this, %obj )
{
    Inspector.inspect( %obj );
    Inspector.apply();
}

//------------------------------------------------------------------------------

function WorldEditor::export(%this)
{
    getSaveFilename("~/editor/*.mac|mac file", %this @ ".doExport", "selection.mac");
}

function WorldEditor::doExport(%this, %file)
{
    saveMission("~/editor/" @ %file, true);
}

function WorldEditor::import(%this)
{
    getLoadFilename("~/editor/*.mac|mac file", %this @ ".doImport");
}

function WorldEditor::doImport(%this, %file)
{
    exec("~/editor/" @ %file);
}

function WorldEditor::onGuiUpdate(%this, %text)
{
}

function WorldEditor::getSelectionLockCount(%this)
{
    %ret = 0;
    for(%i = 0; %i < %this.getSelectionSize(); %i++)
    {
        %obj = %this.getSelectedObject(%i);
        if(%obj.locked)
            %ret++;
    }
    return %ret;
}

function WorldEditor::getSelectionHiddenCount(%this)
{
    %ret = 0;
    for(%i = 0; %i < %this.getSelectionSize(); %i++)
    {
        %obj = %this.getSelectedObject(%i);
        if(%obj.hidden)
            %ret++;
    }
    return %ret;
}

function WorldEditor::dropCameraToSelection(%this)
{
    if(%this.getSelectionSize() == 0)
        return;

    %pos = %this.getSelectionCentroid();
    %cam = Game.camera.getTransformF();

    // set the pnt
    %cam = setWord(%cam, 0, getWord(%pos, 0));
    %cam = setWord(%cam, 1, getWord(%pos, 1));
    %cam = setWord(%cam, 2, getWord(%pos, 2));

    Game.camera.setTransformF(%cam);
}

/// Pastes the selection at the same place (used to move obj from a group to another)
function WorldEditor::moveSelectionInPlace(%this)
{
    %saveDropType = %this.dropType;
    %this.dropType = "atCentroid";
    %this.copySelection();
    %this.deleteSelection();
    %this.pasteSelection();
    %this.dropType = %saveDropType;
}

function WorldEditor::addSelectionToAddGroup(%this)
{
    for(%i = 0; %i < %this.getSelectionSize(); %i++)
    {
        %obj = %this.getSelectedObject(%i);
        $InstantGroup.add(%obj);
    }
}

// resets the scale and rotation on the selection set
function WorldEditor::resetTransforms(%this)
{
    %this.addUndoState();

    for(%i = 0; %i < %this.getSelectionSize(); %i++)
    {
        %obj = %this.getSelectedObject(%i);
        %transform = %obj.getTransformF();

        %transform = setWord(%transform, 3, "0");
        %transform = setWord(%transform, 4, "0");
        %transform = setWord(%transform, 5, "1");
        %transform = setWord(%transform, 6, "0");

        //
        %obj.setTransformF(%transform);
        %obj.setScale("1 1 1");
    }
}


function WorldEditorToolbarDlg::init(%this)
{
    WorldEditorInspectorCheckBox.setValue( WorldEditorToolFrameSet.isMember( "EditorToolInspectorGui" ) );
    WorldEditorTreeCheckBox.setValue( WorldEditorToolFrameSet.isMember( "EditorToolTreeViewGui" ) );
    WorldEditorCreatorCheckBox.setValue( WorldEditorToolFrameSet.isMember( "EditorToolCreatorGui" ) );
}

function WorldEditor::onAddSelected(%this,%obj)
{
    EditorTree.addSelectionObjectId(%obj);
}

function WorldEditor::onWorldEditorUndo( %this )
{
    Inspector.refresh();
}

function Inspector::onInspectorFieldModified( %this, %object, %fieldName, %arrayIndex, %oldValue, %newValue )
{
    // The instant group will try to add our
    // UndoAction if we don't disable it.
    pushInstantGroup();

    %nameOrClass = %object.getName();
    if ( %nameOrClass $= "" )
        %nameOrClass = %object.getClassname();

    %action = new InspectorFieldUndoAction()
    {
        actionName = %nameOrClass @ "." @ %fieldName @ " Change";

        objectId = %object.getId();
        fieldName = %fieldName;
        fieldValue = %oldValue;
        arrayIndex = %arrayIndex;

        inspectorGui = %this;
    };

    // If it's a datablock, initiate a retransmit.  Don't do so
    // immediately so as the actual field value will only be set
    // by the inspector code after this method has returned.

    if( %object.isMemberOfClass( "SimDataBlock" ) )
        %object.schedule( 1, "reloadOnLocalClient" );

    // Restore the instant group.
    popInstantGroup();

    %action.addToManager( Editor.getUndoManager() );
    EWorldEditor.isDirty = true;

    // Update the selection
    if(EWorldEditor.getSelectionSize() > 0 && (%fieldName $= "position" || %fieldName $= "rotation" || %fieldName $= "scale"))
    {
        EWorldEditor.invalidateSelectionCentroid();
    }
}

function Inspector::onFieldSelected( %this, %fieldName, %fieldTypeStr, %fieldDoc )
{
    FieldInfoControl.setText( "<font:ArialBold:14>" @ %fieldName @ "<font:ArialItalic:14> (" @ %fieldTypeStr @ ") " NL "<font:Arial:14>" @ %fieldDoc );
}

// The following three methods are for fields that edit field value live and thus cannot record
// undo information during edits.  For these fields, undo information is recorded in advance and
// then either queued or disarded when the field edit is finished.

function Inspector::onInspectorPreFieldModification( %this, %fieldName, %arrayIndex )
{
    pushInstantGroup();
    %undoManager = Editor.getUndoManager();

    %numObjects = %this.getNumInspectObjects();
    if( %numObjects > 1 )
    %action = %undoManager.pushCompound( "Multiple Field Edit" );

    for( %i = 0; %i < %numObjects; %i ++ )
    {
        %object = %this.getInspectObject( %i );

        %nameOrClass = %object.getName();
        if ( %nameOrClass $= "" )
            %nameOrClass = %object.getClassname();

        %undo = new InspectorFieldUndoAction()
        {
            actionName = %nameOrClass @ "." @ %fieldName @ " Change";

            objectId = %object.getId();
            fieldName = %fieldName;
            fieldValue = %object.getFieldValue( %fieldName, %arrayIndex );
            arrayIndex = %arrayIndex;

            inspectorGui = %this;
        };

        if( %numObjects > 1 )
            %undo.addToManager( %undoManager );
        else
        {
            %action = %undo;
            break;
        }
    }

    %this.currentFieldEditAction = %action;
    popInstantGroup();
}

function Inspector::onInspectorPostFieldModification( %this )
{
    if( %this.currentFieldEditAction.isMemberOfClass( "CompoundUndoAction" ) )
    {
        // Finish multiple field edit.
        Editor.getUndoManager().popCompound();
    }
    else
    {
        // Queue single field undo.
        %this.currentFieldEditAction.addToManager( Editor.getUndoManager() );
    }

    %this.currentFieldEditAction = "";
    EWorldEditor.isDirty = true;
}

function Inspector::onInspectorDiscardFieldModification( %this )
{
    %this.currentFieldEditAction.undo();

    if( %this.currentFieldEditAction.isMemberOfClass( "CompoundUndoAction" ) )
    {
        // Multiple field editor.  Pop and discard.
        Editor.getUndoManager().popCompound( true );
    }
    else
    {
        // Single field edit.  Just kill undo action.
        %this.currentFieldEditAction.delete();
    }

    %this.currentFieldEditAction = "";
}

function Inspector::inspect( %this, %obj )
{
    debug( "inspecting: " @ %obj );

    %name = "";
    if ( isObject( %obj ) )
        %name = %obj.getName();
    else
        FieldInfoControl.setText( "" );

    //InspectorNameEdit.setValue( %name );
    Parent::inspect( %this, %obj );
}

function Inspector::onBeginCompoundEdit( %this )
{
    Editor.getUndoManager().pushCompound( "Multiple Field Edit" );
}

function Inspector::onEndCompoundEdit( %this )
{
    Editor.getUndoManager().popCompound();
}

function Inspector::onCancelCompoundEdit( %this )
{
    Editor.getUndoManager().popCompound( true );
}

function foCollaps (%this, %tab){
    switch$ (%tab){
        case "container0":
            %tab.visible = "0";
            buttxon1.position = getWord(buttxon0.position, 0)+32 SPC getWord(buttxon1.position, 1);
            buttxon2.position = getWord(buttxon1.position, 0)+32 SPC getWord(buttxon2.position, 1);
        case "container1":
            %tab.visible = "0";
        case "container2":
            %tab.visible = "0";
    }
}